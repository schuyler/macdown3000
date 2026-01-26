# MacDown Scroll Synchronization: Complete Technical Guide

## Overview

MacDown synchronizes scroll positions between the editor (left pane) and preview (right pane) using a **reference point interpolation** algorithm. The system tracks headers and standalone images in both panes and maps positions between them proportionally.

## Key Components

### Instance Variables and Properties

| Name | Type | Purpose |
|------|------|---------|
| `_editorHeaderLocations` | `NSArray<NSNumber *>` | Y-coordinates of headers/images in editor |
| `_webViewHeaderLocations` | `NSArray<NSNumber *>` | Y-coordinates of headers/images in preview |
| `_inEditing` | `BOOL` | Blocks sync during active text editing |
| `_inLiveScroll` | `BOOL` | Blocks sync during trackpad/mouse scrolling |
| `shouldHandleBoundsChange` | `BOOL` | Guards `editorBoundsDidChange:` |
| `shouldHandlePreviewBoundsChange` | `BOOL` | Guards `previewBoundsDidChange:` |
| `lastPreviewScrollTop` | `CGFloat` | Persists preview scroll across re-renders |
| `alreadyRenderingInWeb` | `BOOL` | Prevents overlapping renders |
| `renderToWebPending` | `BOOL` | Queues render if one is in progress |

### Core Methods

| Method | Direction | Purpose |
|--------|-----------|---------|
| `syncScrollers` | Editor → Preview | Scrolls preview to match editor position |
| `syncScrollersReverse` | Preview → Editor | Scrolls editor to match preview position |
| `updateHeaderLocations` | Both | Builds reference point arrays for both panes |
| `performDelayedSyncScrollers` | N/A | Timer-based sync after editing (primary path) |

---

## Reference Point Detection

### Editor Detection (`updateHeaderLocations` - Objective-C)

Parses markdown text line-by-line to find:

1. **ATX Headers**: Lines starting with `#` followed by space (e.g., `# Title`)
2. **Setext Headers**: Lines of dashes (`---`) following a content line
3. **Standalone Images**: Lines containing only `![alt](url)` or `![alt][ref]`

**Special handling:**
- Fenced code blocks (` ``` ` or `~~~`) are tracked; headers inside are skipped
- Horizontal rules (3+ `-`, `*`, or `_` with optional spaces) are NOT headers
- Setext vs HR disambiguation uses `previousLineHadContent` flag

**Output:** Array of Y-coordinates (in editor coordinate space) via `NSLayoutManager`.

### Preview Detection (`updateHeaderLocations.js` - JavaScript)

Queries the DOM to find:

1. **Headers**: `document.querySelectorAll('h1, h2, h3, h4, h5, h6')`
2. **Standalone Images**: `<img>` elements that are:
   - Alone in a `<p>` element, OR
   - Wrapped in `<a>` that's alone in `<p>`, OR
   - The only child of their parent

**Output:** Array of Y-coordinates relative to viewport.

---

## Sync Algorithm

Both `syncScrollers` and `syncScrollersReverse` use the same algorithm:

### 1. Find Bounding Reference Points

```
currY = current scroll position

For each reference point Y:
  if Y < currY:
    relativeHeaderIndex++
    minY = Y  (reference point ABOVE current position)
  else if first one past currY and not in last screen:
    maxY = Y  (reference point BELOW current position)
```

If no `maxY` found (near end of document), use document end instead.

### 2. Calculate Interpolation Percentage

```
percentScrolled = (currY - minY) / (maxY - minY)
```

Clamped to [0.0, 1.0].

### 3. Map to Target Pane

```
targetY = topHeaderY + (bottomHeaderY - topHeaderY) * percentScrolled
```

Where `topHeaderY` and `bottomHeaderY` are the corresponding reference points in the target pane.

### 4. Apply Tapering

Near document edges, a "taper" factor reduces the center-alignment adjustment:

```
topTaper = MIN(1.0, currY / visibleHeight)           // 0 at top, 1.0 after one screen
bottomTaper = 1.0 - MIN(1.0, (currY - contentHeight + 2*visibleHeight) / visibleHeight)
adjustmentForScroll = topTaper * bottomTaper * visibleHeight / 2
```

This shifts reference points by half the visible height mid-document, but gradually reduces to zero at document edges.

---

## Trigger Hierarchy

### User Typing Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ User Types Character                                            │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ editorTextDidChange:                                            │
│   • Sets _inEditing = YES                                       │
│   • Schedules performDelayedSyncScrollers (0.7s fallback)       │
│   • Calls [renderer parseAndRenderLater]                        │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ renderer:didProduceHTMLOutput:                                  │
│   • If alreadyRenderingInWeb: set renderToWebPending, return    │
│   • Set alreadyRenderingInWeb = YES                             │
│   • Try DOM replacement path (if preview ready, same base URL)  │
│   • Otherwise: full reload via loadHTMLString                   │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼ (DOM replacement path)
┌─────────────────────────────────────────────────────────────────┐
│ JavaScript Execution                                            │
│   body.innerHTML = newContent                                   │
│   Prism.highlightAll() / MathJax.typeset()                      │
│   requestAnimationFrame → scrollTo(savedY)                      │
│   Sets alreadyRenderingInWeb = NO                               │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼ (after 0.7s timer fires)
┌─────────────────────────────────────────────────────────────────┐
│ performDelayedSyncScrollers (ISSUE #282 FIX)                    │
│   • Guard: if !editorSyncScrolling → clear _inEditing, return   │
│   • Guard: if _inLiveScroll → skip sync                         │
│   • @synchronized: set BOTH guards to NO                        │
│   • updateHeaderLocations                                       │
│   • syncScrollers                                               │
│   • Restore both guards to YES                                  │
│   • Set _inEditing = NO  ← AFTER sync completes                 │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ syncScrollers                                                   │
│   • Calculate target preview Y                                  │
│   • Set shouldHandlePreviewBoundsChange = NO                    │
│   • preview.contentView.bounds.origin.y = targetY               │
│   • Set shouldHandlePreviewBoundsChange = YES                   │
└─────────────────────────────────────────────────────────────────┘
```

### User Scrolling Editor Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ User Scrolls Editor (trackpad/mouse)                            │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ willStartLiveScroll:                                            │
│   • updateHeaderLocations                                       │
│   • _inLiveScroll = YES                                         │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼ (during scroll)
┌─────────────────────────────────────────────────────────────────┐
│ editorBoundsDidChange: (multiple times)                         │
│   • Guard: if !shouldHandleBoundsChange → return                │
│   • Guard: if _inLiveScroll || _inEditing → skip sync           │
│   • Set shouldHandleBoundsChange = NO                           │
│   • updateHeaderLocations                                       │
│   • syncScrollers                                               │
│   • Set shouldHandleBoundsChange = YES                          │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼ (scroll ends)
┌─────────────────────────────────────────────────────────────────┐
│ didEndLiveScroll:                                               │
│   • _inLiveScroll = NO                                          │
└─────────────────────────────────────────────────────────────────┘
```

### User Scrolling Preview Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ previewBoundsDidChange:                                         │
│   • Guard: if !shouldHandlePreviewBoundsChange → return         │
│   • Guard: if _inLiveScroll || _inEditing → skip sync           │
│   • Set shouldHandlePreviewBoundsChange = NO                    │
│   • updateHeaderLocations                                       │
│   • syncScrollersReverse                                        │
│   • Set shouldHandlePreviewBoundsChange = YES                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Guard Mechanisms

### Purpose of Each Guard

| Guard | Set When | Cleared When | Prevents |
|-------|----------|--------------|----------|
| `_inEditing` | Text changes start | DOM replacement completes OR timer fires | Sync during typing |
| `_inLiveScroll` | Trackpad scroll starts | Trackpad scroll ends | Sync interrupting user scroll |
| `shouldHandleBoundsChange` | Before programmatic editor scroll | After scroll | Editor bounds→sync cascade |
| `shouldHandlePreviewBoundsChange` | Before programmatic preview scroll | After scroll | Preview bounds→sync cascade |

### Issue #282: Cascade Prevention (RESOLVED)

**Root Cause:** `_inEditing` was cleared BEFORE `syncScrollers` ran, allowing `previewBoundsDidChange` to trigger `syncScrollersReverse`, causing a ping-pong effect.

**Fix:**
1. Clear `_inEditing` AFTER sync block completes
2. Set BOTH `shouldHandleBoundsChange` AND `shouldHandlePreviewBoundsChange` to NO during sync

**Code pattern:**
```objc
@synchronized(self) {
    self.shouldHandleBoundsChange = NO;
    self.shouldHandlePreviewBoundsChange = NO;
    [self updateHeaderLocations];
    [self syncScrollers];
    self.shouldHandleBoundsChange = YES;
    self.shouldHandlePreviewBoundsChange = YES;
}
_inEditing = NO;  // AFTER sync completes
```

**Pitfall:** Do not call `invokeRenderCompletionHandlers` in the early return path when sync scrolling is disabled. The handlers expect header locations to be updated and scroll to be synced. Calling them without those preconditions breaks the preview.

**Known Limitation:** The DOM replacement path (JS `scrollTo()`) is not explicitly guarded. It relies on `_inEditing` still being YES when the scroll fires, which prevents `previewBoundsDidChange` from triggering reverse sync. This works because the 0.7s timer hasn't fired yet, but it's timing-dependent rather than explicit. A more robust fix would set `shouldHandlePreviewBoundsChange = NO` before JS execution, but this requires changes to the JS/ObjC bridge.

---

## Timing-Based Code Analysis

The scroll sync system has several timing-based mechanisms. Fixed timing is brittle and should be replaced with event-driven callbacks where possible.

### Current Timing Mechanisms

| Mechanism | Location | Duration | Purpose |
|-----------|----------|----------|---------|
| Fallback timer | `editorTextDidChange:` | 0.7s | Sync if JS callback never fires |
| Polling loop | `MPRenderer.m` | 0.5s max | Wait for WebView to load |
| Double rAF | JS DOM replacement | ~32ms | Wait for layout + scroll |

### Replacement Recommendations

#### 1. Polling Loop (MPRenderer.m) - **SHOULD REPLACE**

**Current:** Polls `rendererLoading` in a while loop with 0.5s timeout.

**Problem:** Blocks thread, wastes CPU, arbitrary timeout.

**Solution:** Use WebView delegate `webView:didFinishLoadForFrame:` with completion handler pattern:
```objc
// Instead of polling:
dispatch_semaphore_t loadComplete = dispatch_semaphore_create(0);
self.loadCompletionHandler = ^{ dispatch_semaphore_signal(loadComplete); };
dispatch_semaphore_wait(loadComplete, dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC));

// Delegate signals completion:
- (void)webView:(WebView *)webView didFinishLoadForFrame:(WebFrame *)frame {
    if (self.loadCompletionHandler) self.loadCompletionHandler();
}
```

#### 2. Timer-Based Sync (editorTextDidChange:) - **PRIMARY MECHANISM**

**Current:** 0.7s timer calls `performDelayedSyncScrollers` after text changes.

**Purpose:** Primary sync mechanism that:
- Waits for render to complete before syncing
- Contains the Issue #282 cascade prevention fix
- Works for both DOM replacement and full reload paths

**Note:** This is timer-based rather than event-driven. A future improvement would be to add a JS callback after DOM replacement completes.

#### 3. Double requestAnimationFrame (JS) - **KEEP (JUSTIFIED)**

**Current:**
```javascript
requestAnimationFrame(function() {
    window.scrollTo(0, scrollY);
    requestAnimationFrame(window.__macdownDOMReady);
});
```

**Purpose:**
1. First rAF: Wait for layout after `innerHTML` assignment
2. Second rAF: Wait for scroll position to apply after `scrollTo()`

**Justification:** This is standard browser practice. `requestAnimationFrame` is the correct API for waiting on rendering. No fixed timing - it fires when the browser is ready.

**Alternative (optional):** Could use MutationObserver for DOM changes + single rAF:
```javascript
var observer = new MutationObserver(function() {
    observer.disconnect();
    window.scrollTo(0, scrollY);
    requestAnimationFrame(window.__macdownDOMReady);
});
observer.observe(document.body, { childList: true, subtree: true });
document.body.innerHTML = newHTML;
```

---

## Render Paths

### DOM Replacement Path (Fast)

Used when:
- Preview is ready (`isPreviewReady == YES`)
- Same base URL as current
- MathJax disabled
- CSS styles unchanged

Flow:
1. Extract `<body>` content from HTML
2. Execute JS: `body.innerHTML = content`
3. Wait for `requestAnimationFrame` (layout complete)
4. Restore scroll position via `scrollTo()`
5. Set `alreadyRenderingInWeb = NO`
6. Sync handled by timer-based `performDelayedSyncScrollers` (0.7s)

### Full Reload Path (Slow)

Used when:
- First load
- Base URL changed
- MathJax enabled
- CSS styles changed

Flow:
1. `loadHTMLString:baseURL:` starts async load
2. WebView delegate `webView:didFinishLoadForFrame:` fires
3. Sets `alreadyRenderingInWeb = NO`
4. If `renderToWebPending`: triggers another render
5. Calls `invokeRenderCompletionHandlers`

**Note:** Full reload path uses `MPGetPreviewLoadingCompletionHandler` which calls `syncScrollers` directly (checking `!inEditing`).

---

## File Locations

| File | Contains |
|------|----------|
| `MacDown/Code/Document/MPDocument.m` | All sync logic, notification handlers |
| `MacDown/Resources/updateHeaderLocations.js` | Preview header/image detection |
| `MacDown/Code/Document/MPRenderer.m` | Markdown parsing, render scheduling |
| `MacDownTests/MPScrollSyncTests.m` | 89 unit tests for scroll sync |

---

## Testing

### Automated Tests (MPScrollSyncTests.m)

89 tests covering:
- Header detection (ATX, Setext)
- Horizontal rule disambiguation
- Standalone image detection
- Guard state management
- Cascade prevention (Issue #282)
- Edge cases (nil locations, rapid calls)

Key test methods for Issue #282:
- `testPerformDelayedSyncScrollersSetsPreviewBoundsGuard`
- `testInEditingClearedAfterSync`
- `testSyncScrollersWithGuardsAlreadySet`
- `testSyncScrollersReverseWithGuardsAlreadySet`
- `testRapidSyncCallsDoNotCrash`
- `testGuardsRestoredAfterSyncWithNilLocations`
- `testAlternatingSyncCallsMaintainGuardState`

### Manual Testing

To capture logs for debugging:
```bash
# Launch from terminal to capture NSLog output
"/path/to/MacDown 3000.app/Contents/MacOS/MacDown 3000" > /tmp/macdown.log 2>&1 &

# Open test document
open -a "/path/to/MacDown 3000.app" /path/to/test.md

# Watch logs
tail -f /tmp/macdown.log
```

Test scenarios for Issue #282:
1. Open long document (help.md)
2. Scroll to end of document
3. Press Enter repeatedly - should NOT see alternating jumps
4. Type rapidly - preview should stay stable
5. Paste large text block - no jumping

### Debug Logging (when needed)

Add temporarily for debugging:
```objc
// In performDelayedSyncScrollers
NSLog(@"performDelayedSyncScrollers: editorHeaders=%lu, previewHeaders=%lu",
      (unsigned long)[_editorHeaderLocations count],
      (unsigned long)[_webViewHeaderLocations count]);

// In syncScrollers (jump detection)
CGFloat delta = previewY - previewBefore;
if (fabs(delta) > 100) {
    NSLog(@"syncScrollers: JUMP delta=%.1f, headerIdx=%ld", delta, relativeHeaderIndex);
}
```

---

## Future Improvements

1. **Add event-driven sync callback** - Replace timer-based `performDelayedSyncScrollers` with a JS callback after DOM replacement completes
2. **Replace MPRenderer.m polling** with WebView delegate + completion handler
3. **Reduce sync timer** from 0.7s to 300ms after verifying stability
4. **Consider MutationObserver** pattern in JS for cleaner DOM change detection
4. **WKWebView migration** would provide cleaner APIs for all of this
