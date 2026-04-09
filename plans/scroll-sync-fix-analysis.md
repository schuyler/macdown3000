# Scroll Sync Jump Bug — Analysis and Fix Design

**Issue:** #342 (regression from #282 fix)
**Symptom:** While typing at the end of a long document, the editor pane jumps upward to a mid-document position approximately 200ms after each keystroke.
**Status:** Design verified; ready for implementation.

---

## Reproduction Case

A document with:
- One heading (`# Lorem Ipsum`) near the top
- Long Lorem Ipsum paragraphs filling the middle
- A labeled anchor location mid-document (user called it "-> REFOCUS" because that's where the jump consistently lands)
- More paragraphs, then long lines like `123456789 123456789 123456789` at the bottom

Trigger: type a space after the last number sequence. The editor scrolls upward to mid-document ~200ms later.

---

## What Was Previously "Fixed"

Issue #282 introduced `_inEditing` / `_inLiveScroll` / `shouldHandleBoundsChange` / `shouldHandlePreviewBoundsChange` boolean flags and a 200ms delayed sync (`performDelayedSyncScrollers`). That approach reduced the frequency of jumping but did not eliminate it, because the flags cannot close a race with deferred WebKit scroll notifications.

---

## Root Cause Analysis

Three rounds of independent analysis converged on the following findings.

### The Exact Failure Sequence

1. User types at the bottom of the document. `editorTextDidChange:` fires.
2. `_inEditing = YES`. `performDelayedSyncScrollers` is scheduled for +200ms.
3. The render pipeline fires asynchronously. `renderer:didProduceHTMLOutput:` runs.
4. DOM replacement executes: `body.innerHTML = html`, then `window.scrollTo(0, scrollBefore)` in JS.
5. `window.scrollTo` triggers a `NSViewBoundsDidChangeNotification` on the preview clip view. This notification is dispatched **asynchronously** by WebKit — it arrives on the next run loop turn, not during the JS evaluation.
6. While the notification is queued, `previewBoundsDidChange:` has not fired yet. `_inEditing` is still YES, so if it fired now it would be blocked. It hasn't fired yet.
7. **200ms later:** `performDelayedSyncScrollers` fires. It calls `updateHeaderLocations`, then `syncScrollers`, then restores `shouldHandlePreviewBoundsChange = YES`, then sets `_inEditing = NO`.
8. The queued WebKit bounds notification from step 5 now fires. Both guards (`shouldHandlePreviewBoundsChange` and `_inEditing`) are now clear.
9. `previewBoundsDidChange:` calls `syncScrollersReverse`.
10. `syncScrollersReverse` reads the current preview scroll position — which is `scrollBefore`, the value passed to `window.scrollTo` in step 4. `scrollBefore` was captured before the DOM replacement from the *previous* render cycle, not derived from the current editor position.
11. `syncScrollersReverse` maps `scrollBefore` (a stale mid-document position) back to the editor. The editor jumps to mid-document.

**The mid-document position** is wherever `scrollBefore` was when the previous render ran — which is wherever the preview was when the user was last not at the bottom. The user labeled this "-> REFOCUS" because that was its consistent value in their test document.

### Why the 200ms Delay Is the Wrong Fix

The delay creates a guaranteed race window:
- The delayed callback clears `_inEditing` *after* `shouldHandlePreviewBoundsChange` is restored to YES
- The deferred WebKit notification from `window.scrollTo` can arrive in that window
- No combination of boolean flag ordering can close this without canceling the pending notification explicitly — and there is no API to do that

**Conclusion: time-based delays introduce the race condition they were meant to prevent. They must be eliminated entirely.**

---

## Identified Bugs

### Bug A — Deferred WebKit notification bypasses guards

**Location:** `performDelayedSyncScrollers` (~line 2346), `previewBoundsDidChange:` (~line 1515)

`syncScrollers` sets `contentView.bounds` directly in ObjC, which fires `NSViewBoundsDidChangeNotification` *synchronously* — this is correctly suppressed by `shouldHandlePreviewBoundsChange = NO`. But `window.scrollTo(0, scrollBefore)` from the DOM replacement JS fires its notification *asynchronously* on the next run loop turn. By then all guards are down and `_inEditing` is NO.

`@synchronized(self)` provides no protection here — all notification dispatch is on the main thread, and `@synchronized` is reentrant from the same thread. It does nothing useful in this context.

### Bug B — ObjC/JS coordinate read is not atomic

**Location:** `updateHeaderLocations` (~line 2203), `updateHeaderLocations.js`

```objc
// ObjC reads scroll position at time T1
CGFloat offset = NSMinY(self.preview.enclosingScrollView.contentView.bounds);

// JS evaluates getBoundingClientRect().top at time T2
_webViewHeaderLocations = [[context evaluateScript:script] toArray];

// Combined: assumes T1 == T2, which is not guaranteed
[locations addObject:@([location floatValue] + offset)];
```

`getBoundingClientRect().top` is viewport-relative, measured at T2. `offset` is the scroll position at T1. If WebKit commits a pending scroll between T1 and T2 (e.g., processing the `window.scrollTo` from DOM replacement), `rect.top + offset` is wrong by the scroll delta. This corrupts `_webViewHeaderLocations`, causing both sync functions to map scroll percentages to wrong positions.

### Bug C — `MPGetPreviewLoadingCompletionHandler` is unguarded

**Location:** `MPGetPreviewLoadingCompletionHandler` (~line 276)

On full page load (style changes, first open), the completion handler calls `syncScrollers` with no `_inEditing` check. If a full reload completes while the user is typing, `syncScrollers` fires unconditionally. Additionally, the direct `contentView.bounds` assignment at lines 270–271 lacks `shouldHandlePreviewBoundsChange = NO`, meaning it can trigger `syncScrollersReverse` while `_inEditing` is still YES if `_inEditing` happened to be cleared just before the assignment.

### Bug D — Asymmetric header array filtering

**Location:** `updateHeaderLocations` (~line 2318)

```objc
// Editor array: headers in the last visible screen are excluded
if (headerY <= editorContentHeight - editorVisibleHeight) {
    [locations addObject:@(headerY)];
}
```

The JS in `updateHeaderLocations.js` applies no equivalent filter — all headers are returned regardless of position. For documents with a header near the bottom of the editor, `_editorHeaderLocations` and `_webViewHeaderLocations` have different lengths. `relativeHeaderIndex` computed against one array is used as an index into the other, producing off-by-one position lookups in both `syncScrollers` and `syncScrollersReverse`.

### Bug E — `lastPreviewScrollTop` conflates two purposes

`lastPreviewScrollTop` is used both to restore preview scroll after a full page reload and as the `scrollBefore` value passed to `window.scrollTo` in DOM replacement. The value stored is from the last render cycle — it reflects wherever the preview happened to be, not the position corresponding to the current editor cursor. When `scrollBefore` is stale, the deferred `window.scrollTo` notification (Bug A) moves the preview to the wrong location, and `syncScrollersReverse` maps that back to the editor.

---

## Three Structural Problems

These bugs are symptoms of three deeper design problems that cannot be fixed by patching individual races.

### 1. Dual-coordinate-system header locations

`_webViewHeaderLocations` is assembled by combining an ObjC scroll read with a JS layout read. These are never guaranteed to be from the same instant. The correct approach: read document-absolute coordinates entirely from JS in one atomic evaluation.

### 2. Boolean flags cannot close deferred-notification races

WebKit dispatches `window.scrollTo` notifications asynchronously. Boolean flags lowered after `syncScrollers` completes will always be down when the deferred notification arrives. No reordering of flag assignments fixes this — the gap is structural.

### 3. Time-based delay is the wrong synchronization primitive

`performDelayedSyncScrollers` uses 200ms to let "rendering settle." This introduces a race window (Bug A) and provides no actual guarantee that layout is stable. The correct signal is render completion, not elapsed time.

---

## Fix Design

### Principle

Replace all timing-based synchronization with event-driven synchronization. Replace four boolean flags with a single scroll ownership model. Fix the coordinate read race. Align the two header arrays.

### Step 1 — Fix the coordinate read race (Bug B)

Change `updateHeaderLocations.js` to return document-absolute coordinates directly:

```js
// Before
return rect.top;

// After
return window.scrollY + rect.top;
```

Remove the `+ offset` correction loop in `updateHeaderLocations` in `MPDocument.m`. Both reads are now from a single atomic JS evaluation — no ObjC/JS split.

### Step 2 — Replace four boolean flags with a scroll ownership enum (Bugs A, C)

Declare in the private interface:

```objc
typedef NS_ENUM(NSUInteger, MPScrollOwner) {
    MPScrollOwnerEditor,   // Editor is authoritative; preview is a follower
    MPScrollOwnerPreview,  // User is live-scrolling preview; editor follows
    MPScrollOwnerNeither   // Quiescent; sync in either direction is valid
};

@property (nonatomic) MPScrollOwner scrollOwner;
```

Ownership rules:
- `editorTextDidChange:` → `scrollOwner = MPScrollOwnerEditor`
- Render completion (DOM replacement done, MathJax done) → sync editor→preview → `scrollOwner = MPScrollOwnerNeither`
- User begins live-scrolling preview → `scrollOwner = MPScrollOwnerPreview`
- User ends live-scrolling preview → sync preview→editor once → `scrollOwner = MPScrollOwnerNeither`
- User scrolls editor (non-typing) → sync editor→preview → ownership unchanged

Guard rules:
- `previewBoundsDidChange:` → only calls `syncScrollersReverse` if `scrollOwner == MPScrollOwnerPreview`
- `editorBoundsDidChange:` → only calls `syncScrollers` if `scrollOwner == MPScrollOwnerNeither`
- `MPGetPreviewLoadingCompletionHandler` → only calls `syncScrollers` if `scrollOwner != MPScrollOwnerEditor`

The deferred `window.scrollTo` notification (Bug A) now arrives while `scrollOwner == MPScrollOwnerEditor` — `previewBoundsDidChange:` ignores it. No race window.

**Internal flag toggles inside `syncScrollers` and `syncScrollersReverse` must be removed.** The current code brackets the `contentView.bounds` assignment in each sync function with `shouldHandlePreviewBoundsChange = NO/YES` (in `syncScrollers`, ~lines 2466–2468) and `shouldHandleBoundsChange = NO/YES` (in `syncScrollersReverse`, ~lines 2565–2567). These toggle the old boolean flags to suppress the synchronous `NSViewBoundsDidChangeNotification` fired by the assignment. Under the new model, the ownership guard at the top of `previewBoundsDidChange:` (`scrollOwner != MPScrollOwnerPreview`) and `editorBoundsDidChange:` (`scrollOwner != MPScrollOwnerNeither`) already suppress the reverse sync — the toggles are redundant and must be deleted along with the flags they reference.

**Access pattern:** Use ivar-direct access (`_scrollOwner`) consistent with how `_inEditing` and `_inLiveScroll` are used throughout the file. The `@property` declaration enables KVC/KVO if ever needed, but all internal accesses use the ivar.

**Initial value:** `_scrollOwner` should be initialized to `MPScrollOwnerNeither` in `-init` (quiescent at document open).

### Step 3 — Eliminate `performDelayedSyncScrollers` entirely (Bugs A, E)

Remove the 200ms delayed sync. Instead, call `updateHeaderLocations` + `syncScrollers` at render completion:

- **DOM replacement path (non-MathJax):** After `[context evaluateScript:updateScript]` returns (line 1365), call `updateHeaderLocations` + `syncScrollers` synchronously while `_scrollOwner == MPScrollOwnerEditor`. Then set `_scrollOwner = MPScrollOwnerNeither`. This must occur before the next run loop turn so the deferred `window.scrollTo` notification arrives while ownership is still being set — but since the transition happens before returning from the method, the notification will arrive either in `MPScrollOwnerEditor` (if user typed again) or `MPScrollOwnerNeither` (if not), both of which suppress `syncScrollersReverse`.
- **MathJax path:** In the `DOMReplacementDone` callback, call `updateHeaderLocations` + `syncScrollers` after typesetting, then set `_scrollOwner = MPScrollOwnerNeither`.
- **Full reload path:** In `MPGetPreviewLoadingCompletionHandler`, call `updateHeaderLocations` + `syncScrollers` after the preview is ready (already does this, just needs the ownership guard from Step 2).

**Full reload during typing:** If a full reload fires while `_scrollOwner == MPScrollOwnerEditor`, `syncScrollers` is skipped in the completion handler. The preview may be briefly mispositioned. Recovery is automatic: the render debounce (500ms) fires on the next keystroke or after typing stops, triggering `renderer:didProduceHTMLOutput:` → DOM replacement path → `updateHeaderLocations` + `syncScrollers`. The preview corrects within one render cycle. No additional mechanism is needed.

No timers anywhere in the sync path.

### Step 4 — Fix asymmetric header filtering (Bug D)

Remove the `editorContentHeight - editorVisibleHeight` filter from `_editorHeaderLocations` in `updateHeaderLocations`. Both arrays should contain all headers in document order. The `interpolateToEndOfDocument` logic in `syncScrollers` and `syncScrollersReverse` already handles the end-of-document case correctly; no pre-filtering is needed. This ensures `_editorHeaderLocations[n]` and `_webViewHeaderLocations[n]` always refer to the same heading.

### Step 5 — Fix `lastPreviewScrollTop` (Bug E)

After `syncScrollers` computes and applies the correct preview scroll position, save that value as `lastPreviewScrollTop`. This ensures that if a full reload fires shortly after, the preview restores to the position derived from the editor cursor, not a stale value from a previous render cycle.

---

## What This Does Not Touch

- Hoedown renderer
- WebView lifecycle
- Scroll sync algorithm (`syncScrollers`, `syncScrollersReverse` internals)
- Preview/editor pane split view
- Any test infrastructure

---

## Open Questions — Resolved

### OQ1 — Render debounce timing

**Answer: Confirmed safe; fast typing is handled correctly.**

`MPRenderer.parseAndRenderLater` debounces at **500ms** (`parseAndRenderWithMaxDelay:0.5`). A user typing at 8 chars/sec (125ms between keystrokes) accumulates ~4 keystrokes before the first render fires. During that window, `scrollOwner` stays `MPScrollOwnerEditor` continuously. When render completes, `syncScrollers` runs and ownership transitions to `MPScrollOwnerNeither`. If the user types again before the render, ownership immediately goes back to `MPScrollOwnerEditor`. Ownership never leaks into a state where `previewBoundsDidChange:` could call `syncScrollersReverse`. Confirmed correct.

### OQ2 — `window.scrollTo` ordering in JS closure

**Answer: Ordering is safe in both non-MathJax and MathJax paths.**

In the non-MathJax path, `window.scrollTo(0, scrollY)` is called synchronously inside the JS closure at line 1335. When `[context evaluateScript:updateScript]` returns (line 1365), `window.scrollTo` has already been called but its `NSViewBoundsDidChangeNotification` has not yet fired — WebKit queues it for the next run loop turn. Calling `updateHeaderLocations` + `syncScrollers` synchronously after line 1365 executes before the notification fires. Safe.

In the MathJax path, `window.scrollTo(0, scrollY)` and `invokeCallbackForKey_('DOMReplacementDone')` execute in the same MathJax queue callback. `invokeCallbackForKey_` is synchronous — the ObjC `DOMReplacementDone` block runs during JS evaluation, before the queue callback returns. The deferred WebKit notification from that same `window.scrollTo` call fires on the next run loop turn, after the callback block completes. The ObjC sync therefore runs before the notification. Safe.

### OQ3 — MathJax `DOMReplacementDone` timing

**Answer: No race; the guard model is correct as designed.**

The concern was: after `DOMReplacementDone` transitions `scrollOwner = MPScrollOwnerNeither`, the deferred `window.scrollTo` notification arrives and `previewBoundsDidChange:` fires with `scrollOwner == MPScrollOwnerNeither`. This is safe because **`previewBoundsDidChange:` only calls `syncScrollersReverse` when `scrollOwner == MPScrollOwnerPreview`**. Neither → notification suppressed. No jump.

The one edge case — user starts live-scrolling the preview in the window between the ownership transition and the deferred notification — is also safe. If that happens, `scrollOwner = MPScrollOwnerPreview` reflects the actual user intent, and the notification (which carries the user's actual scroll position) correctly triggers `syncScrollersReverse`. No bad state.

**No timing delays are needed anywhere in the fix.**

---

## Verification Findings

Conducted after multi-agent codebase review. All line numbers are from `MPDocument.m` unless noted.

### Confirmed code references

| Symbol | Actual line | Notes |
|--------|-------------|-------|
| `_inLiveScroll` property | 231 | ivar-direct access pattern throughout |
| `_inEditing` property | 232 | ivar-direct access pattern throughout |
| `shouldHandlePreviewBoundsChange` | 213 | plain `@property BOOL` |
| `shouldHandleBoundsChange` | 212 | plain `@property BOOL` |
| `lastPreviewScrollTop` | 218 | three save sites: 1359, 1371, 2471 |
| `MPGetPreviewLoadingCompletionHandler` | 260 | analysis said ~276; close enough |
| `performDelayedSyncScrollers` impl | 2346 | correct |
| `previewBoundsDidChange:` | 1515 | correct |
| `editorBoundsDidChange:` | 1475 | not given in analysis |
| `updateHeaderLocations` | 2203 | correct |
| DOM replacement / `scrollBefore` | 1312 | not given in analysis |
| `DOMReplacementDone` callback | 1348–1360 | not given in analysis |
| `willStartLiveScroll:` | 1464 | not given in analysis |
| `didEndLiveScroll:` | 1470 | not given in analysis |

### `updateHeaderLocations.js` confirmed

Currently returns `rect.top` (viewport-relative). The Step 1 fix (`window.scrollY + rect.top`) is confirmed necessary.

### `syncScrollers` and `syncScrollersReverse` have their own runtime filters

`syncScrollers` applies a `headerY < editorContentHeight - editorVisibleHeight` filter during iteration (lines 2417–2422). `syncScrollersReverse` applies `headerY < previewContentHeight - previewVisibleHeight` similarly. The pre-filter removed by Step 4 in `updateHeaderLocations` is therefore redundant — the runtime filters handle end-of-document interpolation. Step 4 is safe.

### `MPScrollOwner` visibility

Nothing in `MPDocument.h` exposes the boolean flags. The enum can remain in the private `@interface MPDocument ()` extension in `MPDocument.m`.

### `lastPreviewScrollTop` save sites

- **Line 1359** (MathJax `DOMReplacementDone` callback): saves `newScrollY` — the actual post-MathJax scroll position. Post-sync; correct.
- **Line 1371** (non-MathJax DOM replacement path): saves `scrollBefore` — the pre-replacement scroll position. **Stale; remove this.**
- **Line 2471** (`syncScrollers` end): saves `previewY` — the correctly computed value. This is the canonical save site.

### Identified gaps not in original analysis

**Gap 1 — Missing preview `willStartLiveScroll:` observer registration**

`willStartLiveScroll:` and `didEndLiveScroll:` (lines 1464, 1470) are registered only for `self.editor.enclosingScrollView` (lines 477–482). There is no `NSScrollViewWillStartLiveScrollNotification` observer for `self.preview.enclosingScrollView`. The ownership model requires `scrollOwner = MPScrollOwnerPreview` when the user begins live-scrolling the preview. A new observer registration must be added:

```objc
[center addObserver:self selector:@selector(willStartPreviewLiveScroll:)
               name:NSScrollViewWillStartLiveScrollNotification
             object:self.preview.enclosingScrollView];
```

And a handler:
```objc
- (void)willStartPreviewLiveScroll:(NSNotification *)notification {
    [self updateHeaderLocations];   // Must come first: ensures fresh header locations
    _scrollOwner = MPScrollOwnerPreview;
}
```

`updateHeaderLocations` must be called before setting ownership, so that when `didEndPreviewLiveScroll:` calls `syncScrollersReverse`, it operates on current header positions. This mirrors what the existing `willStartLiveScroll:` (line 1464) does for the editor.

The existing `previewDidLiveScroll:` (line 1509) only saves `lastPreviewScrollTop` — no change needed there. The existing `didEndLiveScroll:` (line 1470) sets `_inLiveScroll = NO`. Under the new model, the parallel `didEndPreviewLiveScroll:` must: call `syncScrollersReverse` once, then set `_scrollOwner = MPScrollOwnerNeither`.

Note: the existing `didEndLiveScroll:` is registered for `self.editor.enclosingScrollView`. The new `didEndPreviewLiveScroll:` must be registered separately for `self.preview.enclosingScrollView`.

**Gap 2 — `close` method cancels `performDelayedSyncScrollers`**

Line 555–557 of `-close` calls:
```objc
[NSObject cancelPreviousPerformRequestsWithTarget:self
                                         selector:@selector(performDelayedSyncScrollers)
                                           object:nil];
```

When `performDelayedSyncScrollers` is removed, this cancellation call must also be removed. Otherwise it produces a misleading dead-code call (and possibly a runtime warning).

**Gap 3 — `MPGetPreviewLoadingCompletionHandler` `contentView.bounds` assignment**

Lines 270–271 directly assign `contentView.bounds` to restore `lastPreviewScrollTop`. This fires `NSViewBoundsDidChangeNotification` on the preview's clip view. Under the new ownership model, during a full reload the `scrollOwner` is typically `MPScrollOwnerNeither` (user not live-scrolling). `previewBoundsDidChange:` would receive this notification. Since `scrollOwner != MPScrollOwnerPreview`, `syncScrollersReverse` is NOT called — the notification is suppressed. **This gap is not actually a gap under the proposed guard model.** The fix for Bug C (guarding the subsequent `syncScrollers` call with `scrollOwner != MPScrollOwnerEditor`) is sufficient.

### Confirmed: no timing delays needed

The ownership enum's guard logic (`previewBoundsDidChange:` → only `MPScrollOwnerPreview` triggers `syncScrollersReverse`) means deferred WebKit notifications arriving in `MPScrollOwnerEditor` or `MPScrollOwnerNeither` states are both safely suppressed without any timer extension. No `dispatch_async`, no `performSelector:afterDelay:`, nothing.

---

## Revised Implementation Order

1. **Step 1 + Step 4** — JS fix and asymmetric filter removal (independent; lowest risk)
2. **Step 2 + Gap 1** — Enum declaration, four-flag replacement, guard logic, preview live-scroll observer registration
3. **Step 3 + Gap 2** — Remove `performDelayedSyncScrollers` and its two call sites (line 1429–1434 in `editorTextDidChange:`, line 555–557 in `-close`); add sync call to non-MathJax DOM replacement completion (after line 1365); update MathJax `DOMReplacementDone` callback guard
4. **Step 5** — Remove stale save at line 1371; `syncScrollers` at line 2471 already saves the correct value

---

## Files to Modify (Revised)

| File | Changes |
|------|---------|
| `MacDown/Code/Document/MPDocument.m` | Replace 4 boolean flags with `MPScrollOwner` enum + property (private); remove `performDelayedSyncScrollers` and all scheduling/cancellation calls; add sync call to non-MathJax DOM replacement completion; guard `MPGetPreviewLoadingCompletionHandler`; remove stale `lastPreviewScrollTop` save (line 1371); remove asymmetric pre-filter from `updateHeaderLocations`; fix `previewBoundsDidChange:` and `editorBoundsDidChange:` guard logic; add preview `willStartLiveScroll` and `didEndLiveScroll` observer registration and handlers; update `DOMReplacementDone` callback guard |
| `MacDown/Code/Document/MPDocument.h` | No changes needed (`MPScrollOwner` stays private) |
| `MacDown/Resources/updateHeaderLocations.js` | Return `window.scrollY + rect.top` instead of `rect.top`; remove ObjC offset correction loop |

---

## Test Design

All tests live in `MacDownTests/MPScrollSyncTests.m`. No new test file is needed.

### Private category additions required

```objc
@interface MPDocument (ScrollSyncTesting)
// Drop: shouldHandleBoundsChange, shouldHandlePreviewBoundsChange, inEditing,
//       inLiveScroll, performDelayedSyncScrollers
// Add:
@property (nonatomic) NSUInteger scrollOwner;  // raw NSUInteger; compare to enum constants
- (void)willStartPreviewLiveScroll:(NSNotification *)notification;
- (void)didEndPreviewLiveScroll:(NSNotification *)notification;
@end
```

`MPScrollOwner` stays private to `MPDocument.m`. Tests use raw `NSUInteger` values (0 = Editor, 1 = Preview, 2 = Neither) or redeclare matching integer constants in the test file.

### Tests to delete (old contract, will fail after fix)

- `testInEditingPropertyDefaultsToNO`
- `testPerformDelayedSyncScrollersExists`
- `testPerformDelayedSyncScrollersClearsInEditing`
- `testPerformDelayedSyncScrollersWithEmptyLocations`
- `testPerformDelayedSyncScrollersWithNilLocations`
- `testInEditingAndShouldHandleBoundsChangeAreIndependent`
- `testPendingDelayedSyncCancelledOnClose`
- `testPerformDelayedSyncScrollersSetsGuards`
- `testInEditingClearedAfterSync`
- `testShouldHandlePreviewBoundsChangeDefaultsToYes`
- `testBothGuardsCanBeSetIndependently`
- `testCascadePreventionBothGuardsSetDuringSync`
- `testCascadePreventionDirectSyncScrollersCleansUp`
- `testRapidEditingCalls`
- `testPreviewBoundsChangeGuardedByInEditing`

### New tests — Group A: Ownership state machine

| Test | Setup | Action | Assert |
|------|-------|--------|--------|
| A1 — initial ownership | fresh alloc/init | read scrollOwner | MPScrollOwnerNeither (2) |
| A2 — editorTextDidChange sets Editor | scrollOwner = Neither | call `editorTextDidChange:nil` | scrollOwner == MPScrollOwnerEditor (0) |
| A3 — willStartPreviewLiveScroll sets Preview | scrollOwner = Neither | call `willStartPreviewLiveScroll:nil` | scrollOwner == MPScrollOwnerPreview (1) |
| A4 — didEndPreviewLiveScroll resets to Neither | scrollOwner = Preview | call `didEndPreviewLiveScroll:nil` | scrollOwner == Neither (2) |
| A5 — repeated editorTextDidChange stays Editor | call once | call again | still MPScrollOwnerEditor |
| A6 — editorTextDidChange during Preview overrides | scrollOwner = Preview | call `editorTextDidChange:nil` | scrollOwner == MPScrollOwnerEditor |

### New tests — Group B: Guard logic

| Test | Setup | Action | Assert |
|------|-------|--------|--------|
| B1 — previewBoundsDidChange suppressed during Editor | scrollOwner = Editor; sync pref on | call `previewBoundsDidChange:nil` | no throw; scrollOwner unchanged |
| B2 — previewBoundsDidChange passes during Preview | scrollOwner = Preview; empty header arrays; sync pref on | call `previewBoundsDidChange:nil` | no throw; scrollOwner still Preview |
| B3 — editorBoundsDidChange suppressed during Editor | scrollOwner = Editor; sync pref on | call `editorBoundsDidChange:nil` | no throw; scrollOwner unchanged |
| B4 — editorBoundsDidChange passes during Neither | scrollOwner = Neither; empty header arrays; sync pref on | call `editorBoundsDidChange:nil` | no throw; scrollOwner still Neither |

### New tests — Group C: JS coordinate fix (JSContext, no WebView)

Mock DOM in JSContext: inject `window = {scrollY: N}`, `document = {body: ..., querySelectorAll: fn}`, `Node = {DOCUMENT_POSITION_FOLLOWING: 4, ...}`. Load and evaluate `updateHeaderLocations.js`.

| Test | scrollY | header rect.top(s) | Expected result |
|------|---------|-------------------|-----------------|
| C1 — scrolled page | 200 | [100] | [300] |
| C2 — unscrolled page | 0 | [150] | [150] |
| C3 — multiple headers | 500 | [50, 100, 300] | [550, 600, 800] |
| C4 — empty body | any | (none) | [] |
| C5 — null body | any | (null document.body) | [] (no crash) |

### New tests — Group D: Header array alignment safety

Inject synthetic `_webViewHeaderLocations` / `_editorHeaderLocations` arrays of equal length.

| Test | Setup | Action | Assert |
|------|-------|--------|--------|
| D1 — equal arrays no OOB | both = @[@100, @300, @600] | syncScrollers | no throw |
| D2 — equal arrays no OOB reverse | both = @[@100, @300, @600] | syncScrollersReverse | no throw |
| D3 — empty arrays | both empty | syncScrollers | no throw |

### New tests — Group E: lastPreviewScrollTop save point

| Test | Setup | Action | Assert |
|------|-------|--------|--------|
| E2 — syncScrollers overwrites lastPreviewScrollTop | lastPreviewScrollTop = 999.0; empty header arrays | syncScrollers | lastPreviewScrollTop != 999.0 (overwritten by sync) |

### New tests — Group F: Handler method existence

| Test | Assert |
|------|--------|
| F1 | `[doc respondsToSelector:@selector(willStartPreviewLiveScroll:)]` |
| F2 | `[doc respondsToSelector:@selector(didEndPreviewLiveScroll:)]` |

### New tests — Group G: performDelayedSyncScrollers removal

| Test | Assert |
|------|--------|
| G1 — method removed | `![doc respondsToSelector:@selector(performDelayedSyncScrollers)]` |
| G2 — close does not crash | `XCTAssertNoThrow([doc close])` |

### Untestable without live WebView (manual verification only)

- Bug A race (deferred WebKit notification) — requires actual WebKit dispatch
- Bug D filter removal in `updateHeaderLocations` — `NSLayoutManager` returns zero-height in headless
- Line 1371 stale save removal — requires `renderer:didProduceHTMLOutput:` which needs a live WebView
- Observer registration for `willStartPreviewLiveScroll:` / `didEndPreviewLiveScroll:` — requires `windowControllerDidLoadNib:`
