# Scroll Synchronization in MacDown 3000

This document describes how scroll synchronization works between the editor and preview panes in MacDown 3000. All scroll sync logic lives in `MPDocument.m`. One JavaScript file, `updateHeaderLocations.js`, provides preview-side measurements.

---

## Architecture

MacDown 3000 displays two panes inside an `MPDocumentSplitView`. Each pane's visibility is determined by its frame width — a pane with zero width is treated as hidden. The preview pane uses the legacy `WebView` (not `WKWebView`; see issue #111 for the planned migration).

Scroll sync keeps the two panes aligned as the user reads and edits. When the user scrolls the editor, the preview follows, and vice versa. The mechanism is reference-point-based rather than proportional: it identifies structural landmarks (headers and standalone images) in both panes, then interpolates between them.

---

## Data Model

Four pieces of state drive scroll sync:

| Field | Type | Description |
|---|---|---|
| `_editorHeaderLocations` | `NSArray<NSNumber *>` | Y-coordinates of headers and standalone images in the editor, computed from `NSLayoutManager` |
| `_webViewHeaderLocations` | `NSArray<NSNumber *>` | Y-coordinates of the same structural elements in the preview, computed via JS DOM queries |
| `lastPreviewScrollTop` | `CGFloat` | Cached preview scroll position. Written by `syncScrollers` on every forward sync and by `didEndPreviewLiveScroll:` after user-initiated preview scrolling. Read by the full-page-load completion handler to restore scroll position after a page load or DOM replacement. |
| `_scrollOwner` | `MPScrollOwner` (enum) | Three-state mutex controlling which pane drives sync |

The ownership enum has three values:

```objc
typedef NS_ENUM(NSUInteger, MPScrollOwner) {
    MPScrollOwnerEditor  = 0,  // Editor is authoritative; preview follows
    MPScrollOwnerPreview = 1,  // User is live-scrolling preview; editor follows
    MPScrollOwnerNeither = 2,  // Quiescent; sync in either direction is valid
};
```

---

## Reference Point Detection

Both panes detect the same set of structural elements: ATX headers (`# Heading`), setext headers (underline-style), and standalone images (image tags on their own line).

**Editor side.** `updateHeaderLocations` (a single method that populates both arrays) runs a regex over the raw Markdown text and uses `NSLayoutManager` to convert character offsets to Y-coordinates in the text view's coordinate system.

**Preview side.** The same `updateHeaderLocations` method evaluates `updateHeaderLocations.js` synchronously via the WebView's `JavaScriptContext`. The script runs `document.querySelectorAll('h1, h2, h3, h4, h5, h6')` and a standalone image query, returning document-absolute Y-coordinates computed as `window.scrollY + getBoundingClientRect().top` for each matched element. The result crosses the JavaScript-to-Objective-C boundary via `JSValue`'s `-toArray` method.

The two arrays must stay parallel — the Nth entry in `_editorHeaderLocations` must correspond to the Nth entry in `_webViewHeaderLocations`. In practice they can diverge because the editor regex matches headers inside code blocks while the JS query does not (issue #375 tracks AST-based detection as a fix). A runtime validation step, `validateHeaderLocationAlignment`, detects count mismatches and truncates both arrays to the shorter length. This prevents index-out-of-bounds errors but discards trailing reference points.

---

## Sync Algorithms

### Forward sync (editor → preview)

`syncScrollers` maps the editor's current scroll position to a preview scroll position.

1. Find the pair of reference points that bracket the editor's current scroll position: the nearest reference point above (`minY`, tracked by `relativeHeaderIndex`) and the first reference point below (`maxY`). An explicit `foundMaxY` boolean tracks whether a lower reference point was found, rather than testing `maxY == 0`, because a legitimate document can have `maxY` equal to zero.
2. Compute how far between those two points the editor currently is, as a percentage (`percentScrolledBetweenHeaders`). Division by zero is guarded: when `maxY <= 0` after normalization, the percentage defaults to 0.
3. Look up the corresponding preview reference points at the same indices in `_webViewHeaderLocations` and interpolate between them using the same percentage.

If no reference point is found below the current position, the algorithm interpolates to the end of the document instead.

Both sync directions apply a "taper" that smoothly transitions between edge-alignment at document boundaries and center-alignment in the interior:

```objc
CGFloat topTaper = MAX(0, MIN(1.0, currY / visibleHeight));
CGFloat bottomTaper = 1.0 - MAX(0, MIN(1.0,
    (currY - contentHeight + 2 * visibleHeight) / visibleHeight));
CGFloat adjustmentForScroll = topTaper * bottomTaper * visibleHeight / 2;
```

At the top of the document (`currY ≈ 0`), `topTaper` is near 0, so there is no center-alignment shift. At the bottom, `bottomTaper` approaches 0. In the middle, both are 1.0 and the full half-visible-height adjustment is applied. This adjustment is subtracted from each reference point's Y-coordinate when finding the bracketing pair and when interpolating.

### Reverse sync (preview → editor)

`syncScrollersReverse` is the mirror image of `syncScrollers`. It reads the preview's current scroll position directly from the clip view bounds, finds bracketing reference points in `_webViewHeaderLocations`, computes the interpolation percentage, and maps to `_editorHeaderLocations`. (`lastPreviewScrollTop` is not consulted — it is only used by the full-page-load completion handler to restore scroll position after a page load.)

---

## Scroll Ownership Model

The ownership enum prevents feedback loops. When the editor scrolls, `syncScrollers` moves the preview — but that preview movement must not trigger `syncScrollersReverse` back, which would move the editor again.

`_scrollOwner` enforces this. Sync handlers check ownership before running:

- `editorBoundsDidChange:` only syncs when `_scrollOwner == MPScrollOwnerNeither`
- `previewBoundsDidChange:` only syncs when `_scrollOwner == MPScrollOwnerPreview`
- `MPGetPreviewLoadingCompletionHandler` always resets ownership to Neither, but only calls `syncScrollers` when `_scrollOwner != MPScrollOwnerEditor`

### State transitions

| Event | New owner |
|---|---|
| Editor text changes | Editor |
| Preview live-scroll begins | Preview |
| Preview live-scroll ends | Neither (with reverse sync + `lastPreviewScrollTop` save in a single handler) |
| Render completion — DOM replacement path | Neither |
| Render completion — full page load path | Neither |
| MathJax render completion (current generation only) | Neither |
| File revert | Editor (guarded by `isPreviewReady`) |
| Checkbox toggle | Editor (conditioned on `needsHtml`) |
| Layout change refresh | No change (only syncs if already Neither) |
| Editor pane revealed | Temporarily Preview during reverse sync, then Neither |
| Initialization | Neither |

---

## Event-Driven Triggers

Sync runs in response to events rather than on a timer.

**Editor scrolling.** `NSViewBoundsDidChangeNotification` on the editor's clip view fires `editorBoundsDidChange:`, which calls `syncScrollers` when the owner is Neither. (Bounds-change notifications fire on scroll; frame-change notifications fire on resize — these are distinct paths.)

**Preview scrolling.** `NSScrollViewWillStartLiveScrollNotification` and `NSScrollViewDidEndLiveScrollNotification` on the preview's scroll view drive the preview scroll cycle. Live-scroll start sets owner to Preview. Live-scroll end saves `lastPreviewScrollTop` first (capturing the live-scroll endpoint), then calls `syncScrollersReverse`, then resets owner to Neither — all in a single consolidated handler to avoid a race between duplicate observer registrations.

**Editing and typing.** `NSTextDidChangeNotification` sets owner to Editor and schedules a render. After render, ownership resets to Neither via the render completion path.

**Render completion — DOM replacement.** When the preview HTML is replaced without a full page load, the handler unconditionally calls `updateHeaderLocations` and `syncScrollers` (subject to the sync-enabled preference), then unconditionally resets ownership to Neither. There is no ownership guard on the DOM replacement path — the guard exists only on the full-page-load path.

**Render completion — full page load.** `MPGetPreviewLoadingCompletionHandler` fires after a complete WebView load. It restores `lastPreviewScrollTop`, then conditionally syncs (guarded by `scrollOwner != MPScrollOwnerEditor`), and finally resets ownership to Neither. The handler uses a weak-to-strong self dance to prevent deallocation mid-block.

**File revert.** Sets owner to Editor (guarded by `isPreviewReady` to avoid affecting initial load). This causes the full-page-load completion handler's sync guard (`scrollOwner != Editor`) to skip `syncScrollers`. The completion handler still restores `lastPreviewScrollTop` to preserve the previous scroll position, then resets ownership to Neither. Forward sync resumes on the next user-initiated scroll.

**Checkbox toggle.** `handleCheckboxToggle:` modifies the editor's `textStorage` directly via `beginEditing`/`replaceCharactersInRange:withString:`/`endEditing`. Since this bypasses `NSTextView`'s input pipeline, `NSTextDidChangeNotification` is not fired. The handler explicitly calls `parseAndRenderLater` and claims Editor ownership, conditioned on the read-only computed property `needsHtml` (which is true when the preview pane is visible). Without a pending render, setting ownership would leave it stuck.

**Layout changes.** Window resize, split-divider drag, full-screen transition, and editor frame changes can all shift Y-coordinates without changing scroll position. `NSViewFrameDidChangeNotification` on the editor fires `editorFrameDidChange:`, and `splitViewDidResizeSubviews:` fires on divider drags. Both use `performSelector:afterDelay:0` to coalesce rapid events into a single `refreshHeaderCacheAfterResize` call deferred to the next run loop iteration. Window resize end and full-screen transitions cancel any pending coalesced call and invoke the refresh directly. The refresh only syncs when the current owner is Neither.

**Panel reveal.** When the editor pane is revealed (becomes visible), a reverse sync runs to position the editor to match the preview. Owner is set to Preview before the sync and reset to Neither after.

---

## MathJax Handling

MathJax rendering is asynchronous. When the user types quickly, a new render can start before the previous MathJax pass completes. The stale callback from the earlier render would then reset ownership and call `syncScrollers` at the wrong time, corrupting scroll state.

`_mathJaxRenderGeneration` is an integer counter that increments each time a new MathJax render begins. The callback captures the generation value at the time it was issued. When the callback fires, it compares its captured generation to the current counter. If they differ, the callback is from a superseded render and is discarded. Only the most recent generation's callback resets ownership and syncs.

This prevents state corruption but does not eliminate the brief visual flash where un-typeset math is visible before MathJax runs.

---

## Known Limitations

**Manual render mode and stuck ownership.** When the user enables manual render (`markdownManualRender`), typing does not trigger a render. Ownership stays Editor after the user types. It does not reset to Neither until the next render completes. Scroll sync is inactive during this window.

**Failed or aborted page load.** If `MPGetPreviewLoadingCompletionHandler` never fires (network error, load aborted), ownership stays stuck in its current state until the next successful render.

**Layout coalescing timing.** The `performSelector:afterDelay:0` pattern defers to the next run loop iteration, which is typically after layout reflow. This is conventional but not contractually guaranteed. A missed reflow would cause sync to use stale Y-coordinates.

**MathJax visual jump.** The generation counter prevents incorrect state transitions but cannot prevent the un-typeset DOM from being briefly visible between DOM replacement and MathJax completion.

**Header array alignment divergence.** The editor regex detects headers inside fenced code blocks; the JS query does not. This causes the two arrays to have different lengths on documents with headers in code blocks. The truncation fix loses trailing reference points, reducing sync accuracy at the bottom of the document (#375).

**Checkbox toggle and syntax highlighting.** Checkbox toggles modify `NSTextStorage` directly, which fires `NSTextStorageDidProcessEditingNotification` but not `NSTextDidChangeNotification`. The syntax highlighter observes the latter, so it does not re-highlight after a checkbox toggle.

**View menu hide/show label staleness.** The View menu items for showing and hiding panes do not update their labels when the panel state changes through other means (issue #377).

---

## Future Work

- **AST-based header detection** (#375): Replace the editor-side regex with an AST walk that is aware of code block boundaries. This would eliminate the primary cause of array alignment divergence.

- **WKWebView migration** (#111): The `WebView` class is deprecated. Migrating to `WKWebView` will require reworking the JavaScript bridge used by `updateHeaderLocations.js` and the DOM replacement path.

- **Checkbox preview toggle writes back to editor** (#376): Currently checkbox state in the preview is not reflected in the saved file.

- **Syntax highlighter re-highlight after checkbox toggle**: Observing `NSTextStorageDidProcessEditingNotification` instead of (or in addition to) `NSTextDidChangeNotification` would make re-highlighting more reliable.

- **Layout coalescing timing**: `NSViewFrameDidChangeNotification` is already used as the observation trigger, but the `performSelector:afterDelay:0` coalescing mechanism inside the handler defers to the next run loop iteration, which is not contractually guaranteed to be after `NSLayoutManager` reflow. A more correct alternative would observe a layout-completion signal from the text container or layout manager directly, but this would be significantly more complex.
