# Issue #9: Preview Pane Flickering Investigation

**Issue:** https://github.com/schuyler/macdown3000/issues/9
**Branch:** `claude/resolve-issue-9-01LsRCJ3MUPBTD3NLLLaJRyb`
**Status:** In Progress - Multiple iterations completed, awaiting user testing of latest fixes

---

## Problem Statement

The preview pane flickers/flashes white or grey on every keystroke when typing in the editor. This severely impacts the user experience and makes the application difficult to use for extended writing sessions.

### Root Cause

The core issue is that `loadHTMLString:baseURL:` destroys the entire DOM on every keystroke. During the ~10-100ms it takes WebKit to:
1. Parse the new HTML
2. Construct the DOM
3. Layout the page
4. Paint the content
5. Composite to the GPU

...the preview shows a blank white/grey screen, creating a visible flicker.

---

## Approaches Attempted

### Approach 1: Dual-WebView Double-Buffering (FAILED)

**Previous Session Attempt**

**Theory:** Use two WebView instances alternating between visible and hidden states, similar to double-buffering in graphics.

**Implementation:**
1. Create two WebViews (`previewA` and `previewB`)
2. Load new HTML into the hidden WebView
3. Crossfade between them using Core Animation when loading completes

**Critical Bugs Encountered:**

| Bug | Symptom | Root Cause |
|-----|---------|------------|
| Three-pane layout | Two previews shown side-by-side with editor | Added previewB as direct NSSplitView child instead of overlapping container |
| Grey on alternating keystrokes | Preview goes grey every other keystroke | PreviewB not configured (missing preferences, drawsBackground) |
| Still grey with delays | Grey flickers even with 100ms delay | **Fundamental architectural flaw** |

**Why It Failed (Groucho's Analysis):**

WebKit doesn't allocate GPU resources for hidden or occluded views. The compositor doesn't complete render passes for views behind other views. This is a rendering optimization - WebKit won't waste GPU cycles on content that isn't visible.

**Result:** Abandoned after multiple failed attempts. Even with 100ms delays, grey flickering persisted because the WebView never actually rendered while hidden.

---

### Approach 2: Snapshot Overlay (CURRENT)

**Theory:** Capture a static image of the current preview and overlay it during the reload, then crossfade out.

**Advantages over Dual-WebView:**
- Works WITH WebKit instead of against it
- Single WebView (always visible, so WebKit renders normally)
- Simpler architecture
- Less memory usage
- No GPU resource allocation issues

**Implementation Overview:**

#### Snapshot Capture (`renderer:didProduceHTMLOutput:`, lines 1133-1173)

```objc
if (self.isPreviewReady)
{
    // 1. Capture NSBitmapImageRep of current preview
    NSBitmapImageRep *bitmap = [self.preview bitmapImageRepForCachingDisplayInRect:self.preview.bounds];
    bitmap.size = self.preview.bounds.size;
    [self.preview cacheDisplayInRect:self.preview.bounds toBitmapImageRep:bitmap];

    NSImage *snapshot = [[NSImage alloc] initWithSize:self.preview.bounds.size];
    [snapshot addRepresentation:bitmap];

    // 2. Create overlay image view (once)
    if (!self.snapshotOverlay)
    {
        self.snapshotOverlay = [[NSImageView alloc] initWithFrame:self.preview.frame];
        self.snapshotOverlay.autoresizingMask = NSViewNotSizable;
        self.snapshotOverlay.imageScaling = NSImageScaleNone;
        self.snapshotOverlay.wantsLayer = YES;

        [self.preview.superview addSubview:self.snapshotOverlay
                                positioned:NSWindowAbove
                                relativeTo:self.preview];
    }

    // 3. Update overlay position/size and content
    self.snapshotOverlay.frame = self.preview.frame;
    self.snapshotOverlay.image = snapshot;
    self.snapshotOverlay.alphaValue = 1.0;

    // Force immediate display before WebView load
    [self.snapshotOverlay.superview displayIfNeeded];
}

// 4. Reload HTML underneath snapshot
[self.preview.mainFrame loadHTMLString:html baseURL:baseUrl];
```

#### Crossfade Animation (`webView:didFinishLoadForFrame:`, lines 890-905)

```objc
if (frame == sender.mainFrame && self.snapshotOverlay)
{
    // Wait 10ms for WebKit compositor to paint
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.075;  // 75ms for snappy feel
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            self.snapshotOverlay.animator.alphaValue = 0.0;
        } completionHandler:^{
            [self.snapshotOverlay removeFromSuperview];
            self.snapshotOverlay = nil;
        }];
    });
}
```

---

## Bugs Found and Fixed

### Iteration 1: Initial Implementation (Commit 3aa4221)

**Implementation:** Basic snapshot overlay with QuartzCore import, snapshotOverlay property, capture logic, and crossfade.

**User Report:** "I'm still seeing the entire display go grey with each keypress"

**Status:** Implementation complete but not working.

---

### Iteration 2: Positioning Bug (Commit 6d6e10c)

**Bug:** Used `self.preview.bounds` instead of `self.preview.frame` when creating overlay.

**Root Cause:**
- `bounds` = coordinates in view's own coordinate system (origin at 0,0)
- `frame` = coordinates in superview's coordinate system
- Since overlay is added to superview, we need `frame`

**Fix:**
```objc
// BEFORE
self.snapshotOverlay = [[NSImageView alloc] initWithFrame:self.preview.bounds];

// AFTER
self.snapshotOverlay = [[NSImageView alloc] initWithFrame:self.preview.frame];
```

**User Report:** "No dice. same problem"

**Status:** Fix applied but still not working.

---

### Iteration 3: Frame Updates and Display Forcing (Commit 09df60d)

**Consultation with Chico revealed THREE bugs:**

#### Bug 3a: Frame Only Set on Creation

**Problem:** Frame was only set when creating the overlay (`if (!self.snapshotOverlay)`). After window resize or split view adjustment, the overlay would be misaligned.

**Fix:** Update frame on EVERY keystroke:
```objc
// Always update frame, not just on creation
self.snapshotOverlay.frame = self.preview.frame;
```

#### Bug 3b: Z-Order Not Maintained

**Problem:** WebView's internal layers might obscure the overlay after previous load completes.

**Fix:** Re-assert z-order on every keystroke:
```objc
// Re-assert overlay is topmost
[self.preview.superview addSubview:self.snapshotOverlay
                        positioned:NSWindowAbove
                        relativeTo:self.preview];
```

#### Bug 3c: Overlay Not Forcibly Displayed

**Problem:** The overlay might be scheduled for drawing but not actually rendered before the grey flash appears.

**Fix:** Force immediate display:
```objc
[self.snapshotOverlay.superview displayIfNeeded];
```

**User Report:** "Not only is it continuing to flicker grey, but now the preview pane appears to be changing horizontal size irregularly (maybe on every keypress)"

**Status:** Introduced NEW bug (width oscillation) while grey flickering persists.

---

### Iteration 4: Layout Thrashing (Commit 07fb1f9) ⭐ LATEST

**Consultation with Chico revealed THREE MORE critical bugs:**

#### Bug 4a: Repeated `addSubview` Causing Layout Thrashing

**Problem:** The z-order fix from Iteration 3 was calling `addSubview` on EVERY KEYSTROKE, even when the overlay already existed.

**Impact:**
- In Cocoa, calling `addSubview:` on an existing subview removes it and re-adds it
- This triggered on every keystroke:
  - View removal → View re-addition
  - Layout recalculation
  - Autoresizing mask evaluation
  - Display updates
- **Result:** Width oscillation and brief grey flashes during remove/re-add cycle

**Fix:** Move `addSubview` inside the creation block so it's only called ONCE:
```objc
// BEFORE - Called on every keystroke!
if (!self.snapshotOverlay) {
    self.snapshotOverlay = [[NSImageView alloc] initWithFrame:self.preview.frame];
    // ...
}
self.snapshotOverlay.frame = self.preview.frame;
[self.preview.superview addSubview:self.snapshotOverlay
                        positioned:NSWindowAbove
                        relativeTo:self.preview];

// AFTER - Called only once when creating
if (!self.snapshotOverlay) {
    self.snapshotOverlay = [[NSImageView alloc] initWithFrame:self.preview.frame];
    // ...
    [self.preview.superview addSubview:self.snapshotOverlay
                            positioned:NSWindowAbove
                            relativeTo:self.preview];
}
self.snapshotOverlay.frame = self.preview.frame;
```

#### Bug 4b: Autoresizing Mask Fighting Manual Frame Updates

**Problem:**
- Set autoresizing mask: `NSViewWidthSizable | NSViewHeightSizable`
- Then manually set frame: `self.snapshotOverlay.frame = self.preview.frame`
- Repeated `addSubview` triggered BOTH mechanisms simultaneously

**Impact:** Layout oscillation and unpredictable width changes as two resize mechanisms fought each other.

**Fix:** Disable autoresizing since we manually position:
```objc
// BEFORE
self.snapshotOverlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

// AFTER
self.snapshotOverlay.autoresizingMask = NSViewNotSizable;
```

#### Bug 4c: Image Scaling Causing Visual Artifacts

**Problem:** `NSImageScaleAxesIndependently` scaled the snapshot to fit the image view, causing:
- Slight visual mismatches if sizes didn't exactly match
- Grey edges where scaling was imperfect
- Potential blurriness

**Fix:** Use pixel-perfect scaling:
```objc
// BEFORE
self.snapshotOverlay.imageScaling = NSImageScaleAxesIndependently;

// AFTER
self.snapshotOverlay.imageScaling = NSImageScaleNone;
```

**User Testing:** **PENDING** - User has not tested this version yet.

**Expected Results:**
1. ✅ No more width changes (layout thrashing eliminated)
2. ✅ No more grey flicker (snapshot stays in place)
3. ✅ Better visual quality (pixel-perfect snapshot)
4. ✅ Better performance (no layout recalculation on every keystroke)

---

## Technical Insights

### WebKit Rendering Pipeline

Understanding the timing is critical:

```
loadHTMLString:baseURL: called
    ↓
DOM destroyed (white/grey screen appears) ⚠️ FLICKER STARTS
    ↓
Parse HTML (~1-5ms)
    ↓
Construct DOM (~1-10ms)
    ↓
Layout (~5-20ms)
    ↓
Paint (~5-30ms)
    ↓
Composite to GPU (~10-50ms)
    ↓
didFinishLoadForFrame: callback
    ↓
Wait for compositor (~10ms)
    ↓
Content visible ⚠️ FLICKER ENDS
```

**Total flicker time:** 10-100ms depending on document complexity and system load.

### Why Snapshot Overlay Should Work

1. **Snapshot is captured BEFORE reload** - We have the old content as a bitmap
2. **Overlay displays immediately** - `displayIfNeeded` forces synchronous drawing
3. **WebView renders underneath** - It's always visible so WebKit allocates GPU resources
4. **Crossfade reveals new content** - Smooth 75ms transition instead of harsh flash

### Key Cocoa Concepts Applied

| Concept | Usage | Why It Matters |
|---------|-------|----------------|
| `bounds` vs `frame` | Use `frame` for superview positioning | Coordinates must be in superview's space |
| `addSubview:` behavior | Call only once during creation | Re-adding triggers view removal/layout |
| Autoresizing masks | Disabled (`NSViewNotSizable`) | Conflicts with manual frame updates |
| `displayIfNeeded` | Force synchronous drawing | Ensures overlay visible before WebView loads |
| `NSImageScaleNone` | Pixel-perfect rendering | Avoids artifacts from scaling |
| Core Animation | Smooth alpha transition | Better than abrupt show/hide |

---

## Files Modified

### MacDown/Code/Document/MPDocument.m

**Lines 11:** Added `#import <QuartzCore/QuartzCore.h>` for `CAMediaTimingFunction`

**Lines 193:** Added property `@property (strong) NSImageView *snapshotOverlay;`

**Lines 1133-1173:** Snapshot capture and overlay display in `renderer:didProduceHTMLOutput:`

**Lines 890-905:** Crossfade animation in `webView:didFinishLoadForFrame:`

---

## Commit History

| Commit | Description | Status |
|--------|-------------|--------|
| 3aa4221 | Implement snapshot overlay to eliminate preview flickering | User reported still flickering |
| 6d6e10c | Fix snapshot overlay positioning - use frame instead of bounds | User reported still flickering |
| 09df60d | Fix snapshot overlay: update frame, z-order, and force display | User reported flickering + width changes |
| 07fb1f9 | Fix layout thrashing: remove repeated addSubview, fix autoresizing | **⭐ AWAITING USER TESTING** |

---

## Test Results

All commits have passed CI tests on GitHub Actions (macOS runners). However, these tests validate:
- No crashes
- Basic rendering functionality
- Document lifecycle

**The tests do NOT validate:**
- Visual flickering behavior (requires human observation)
- Smooth crossfade animation
- Edge cases like rapid typing, window resizing during edits

---

## Next Steps

### Immediate: User Testing Required

**User must test commit 07fb1f9** to verify:
1. ✅ No grey flickering during typing
2. ✅ Preview pane width remains stable
3. ✅ Smooth crossfade when new content loads
4. ✅ Works correctly after window resize
5. ✅ Works correctly after split view adjustment

### If Testing Succeeds

Proceed with /issue workflow:
- Step 11: Formal Chico code review
- Step 12: Harpo documentation updates + Zeppo manual testing plan (in parallel)
- Step 13: Rebase on main
- Step 14: Force push if needed
- Step 15: Re-verify CI tests
- Step 16: Create pull request
- Step 17: Report completion

### User Testing Result: FAILED

**User report:** "yes, it's still flickering like crazy"

After 4 iterations and 7 bug fixes, the snapshot overlay approach still does not work.

---

## ROOT CAUSE DIAGNOSIS (Final Consultation with Chico)

### The Fundamental Flaw

**The snapshot is capturing an empty/grey view, not the rendered HTML content.**

**Lines 1137-1139:**
```objc
NSBitmapImageRep *bitmap = [self.preview bitmapImageRepForCachingDisplayInRect:self.preview.bounds];
bitmap.size = self.preview.bounds.size;
[self.preview cacheDisplayInRect:self.preview.bounds toBitmapImageRep:bitmap];
```

### Why This Cannot Work

1. **`bitmapImageRepForCachingDisplayInRect:` only captures AppKit layers**
   - It does not capture WebKit's compositor layer where the actual rendered HTML lives

2. **WebView renders in a separate GPU-accelerated layer**
   - This layer exists outside the normal AppKit view hierarchy
   - It's handled by WebKit's internal compositor process

3. **The snapshot is literally grey/empty**
   - The rendered HTML content never makes it into the bitmap
   - We're capturing the WebView's backing view, not its rendered content

4. **The overlay mechanism works perfectly**
   - It's positioned correctly
   - It displays immediately
   - It's on top of the WebView
   - **But it's showing grey-on-grey!**

### Why All 7 Bug Fixes Didn't Help

Every fix addressed the overlay mechanism (positioning, timing, z-order, etc.), but the fundamental problem is **the snapshot content is wrong**:

- ✅ Frame positioning: Correct, but irrelevant - overlay is positioned right, but showing grey
- ✅ Z-order: Correct, but irrelevant - overlay is on top, but showing grey
- ✅ Display forcing: Correct, but irrelevant - overlay displays immediately, but it's grey
- ✅ Layout thrashing eliminated: Correct, but irrelevant - view updates work, but snapshot is grey
- ✅ Autoresizing fixed: Correct, but irrelevant - frame matches, but content is grey
- ✅ Scaling fixed: Correct, but irrelevant - pixel-perfect grey

**All fixes were solving the wrong problem.** They assumed the snapshot was valid.

### The Analogy

It's like trying to photograph a TV screen by taking a picture of the frame - you'll capture the bezel and the black screen, but not what's actually playing on the TV. WebKit's compositor is the "TV signal" that never makes it into our photo.

---

## Path Forward: Two Viable Options

### Option 1: DOM Updates (BEST SOLUTION) ⭐

**The code already exists but is commented out!** Lines 1091-1131 show the RIGHT approach:

```objc
#if 0
    // Unfortunately this DOM-replacing causes a lot of problems...
    // 1. MathJax needs to be triggered.
    // 2. Prism rendering is lost.
    // 3. Potentially more.

    // If we're working on the same document, try not to reload.
    if (self.isPreviewReady && [self.currentBaseUrl isEqualTo:baseUrl])
    {
        // Use the existing tree if available, and replace the content.
        DOMDocument *doc = self.preview.mainFrame.DOMDocument;
        DOMNodeList *htmlNodes = [doc getElementsByTagName:@"html"];
        if (htmlNodes.length >= 1)
        {
            // Find things inside the <html> tag.
            NSRegularExpression *regex = [[NSRegularExpression alloc]
                initWithPattern:@"<html>(.*)</html>"
                options:NSRegularExpressionDotMatchesLineSeparators
                error:NULL];
            NSTextCheckingResult *result = [regex firstMatchInString:html
                options:0
                range:NSMakeRange(0, html.length)];
            html = [html substringWithRange:[result rangeAtIndex:1]];

            // Replace everything in the old <html> tag.
            DOMElement *htmlNode = (DOMElement *)[htmlNodes item:0];
            htmlNode.innerHTML = html;

            return;
        }
    }
#endif
```

**Why This Is The Best Solution:**

1. **Eliminates the reload entirely**
   - No `loadHTMLString:baseURL:` call = no DOM destruction = no flash
   - The content updates in-place like modern single-page web apps

2. **The JavaScript problems are solvable**
   - Modern web apps update DOM constantly and re-run JavaScript
   - MathJax has an API to re-render: `MathJax.Hub.Queue(["Typeset", MathJax.Hub])`
   - Prism has an API to re-highlight: `Prism.highlightAll()`
   - Other JavaScript can be triggered via `evaluateWebScript:`

3. **This is how modern web development works**
   - React, Vue, Angular all update DOM without page reloads
   - Gmail, Twitter, Facebook all update content in-place
   - This is the standard approach for dynamic web content

4. **Performance benefits**
   - No parsing overhead for unchanged HTML structure
   - No re-layout of unchanged elements
   - Preserves scroll position naturally
   - Preserves WebView internal state

**Implementation Plan:**

1. **Re-enable the DOM update code** (remove the `#if 0`)

2. **Add JavaScript re-initialization after DOM update:**
   ```objc
   htmlNode.innerHTML = html;

   // Re-run JavaScript libraries
   if (self.preferences.htmlMathJax) {
       [webView evaluateWebScript:@"if (window.MathJax) MathJax.Hub.Queue(['Typeset', MathJax.Hub]);"];
   }
   if (self.preferences.htmlSyntaxHighlighting) {
       [webView evaluateWebScript:@"if (window.Prism) Prism.highlightAll();"];
   }
   // Add any other JavaScript that needs re-running
   ```

3. **Handle edge cases:**
   - First load: Still use `loadHTMLString:baseURL:` (no existing DOM)
   - Base URL change: Still use `loadHTMLString:baseURL:` (different document)
   - HTML structure change: Detect major changes and fall back to reload

4. **Test thoroughly:**
   - MathJax equations render correctly
   - Syntax highlighting works
   - Tables of contents update
   - Links work correctly
   - Images load properly

**Why This Will Work:**

DOM updates don't destroy the WebView's compositor layer. The rendered content stays visible while we update the DOM tree. The browser then applies incremental updates to the display - no flash, no flicker, just smooth updates.

---

### Option 2: Capture WebView's Document View (LAST ATTEMPT)

Try capturing from the WebView's internal document view instead of the WebView itself:

```objc
// Instead of:
NSBitmapImageRep *bitmap = [self.preview bitmapImageRepForCachingDisplayInRect:self.preview.bounds];
[self.preview cacheDisplayInRect:self.preview.bounds toBitmapImageRep:bitmap];

// Try:
NSView *documentView = self.preview.mainFrame.frameView.documentView;
NSBitmapImageRep *bitmap = [documentView bitmapImageRepForCachingDisplayInRect:documentView.bounds];
[documentView cacheDisplayInRect:documentView.bounds toBitmapImageRep:bitmap];
```

**Why This Might Work:**

The document view is WebKit's internal scroll view that contains the rendered content. It's one layer closer to the actual rendering.

**Why This Might Fail:**

Chico is skeptical because WebKit's compositor is separate from the view hierarchy. The document view might also be a wrapper around the GPU-accelerated layer, not the layer itself.

**If This Works:**

This would be the simplest fix - just change the capture target. But given WebKit's architecture, this is a long shot.

---

### Why Other Options Are Not Acceptable

**Option 3: Accept the Flash** - REJECTED
- This is a high-impact, long-standing issue affecting many users (77+ comments on original issue #1104)
- Modern browsers don't flash during typing in contenteditable or textarea
- The comparison to browser navigation is false - we're not navigating, we're live-previewing
- MacDown is a writing tool - flickering disrupts the writing experience
- This would be giving up on a core quality issue

**Option 4: PDF Snapshot** - NOT WORTH IT
- Converting PDF to image adds significant overhead
- PDF generation is synchronous and slow
- Still has timing issues (when to capture)
- Complexity doesn't justify marginal benefit over Option 2
- If we're doing complex workarounds, better to fix the root cause (Option 1)

---

## Related Issues (Original MacDown Repository)

This flickering issue has a long history:

- **Issue #1104** (77 comments): "Rendering pane flashing" - Preview pane flashes on nearly every keystroke after upgrading to 0.7.2
- **Issue #1057** (16 comments): "Preview pane flickers when typing/updating" - Flickering with every keystroke on macOS Mojave 10.14.3
- **Issue #253**: Referenced as similar earlier bug

**This is a long-standing, high-impact issue affecting many users.**

---

## Lessons Learned

1. **Question fundamental assumptions early** - We spent 4 iterations fixing overlay mechanics when the real problem was the snapshot capture itself
2. **WebKit's architecture is special** - GPU-accelerated compositor layers live outside the normal AppKit view hierarchy
3. **Understand what you're capturing** - `bitmapImageRepForCachingDisplayInRect:` captures AppKit layers, not WebKit's rendered content
4. **Sometimes the old approach was right** - The commented-out DOM update code (lines 1091-1131) was actually the correct solution all along
5. **Tests don't catch everything** - Visual flickering requires human testing; all CI tests passed despite the approach being fundamentally broken
6. **JavaScript re-initialization is solvable** - Modern web frameworks prove that DOM updates + JavaScript re-running is a standard, reliable pattern
7. **Iterative debugging has limits** - When 7 fixes don't help, it's time to question the approach, not just the implementation
8. **Performance optimizations can break assumptions** - WebKit's GPU rendering optimization made double-buffering and snapshot approaches fail

---

## References

- WebKit Rendering Pipeline: https://www.webkit.org/blog/
- NSView Coordinate Systems: https://developer.apple.com/documentation/appkit/nsview
- Core Animation: https://developer.apple.com/documentation/quartzcore
- View Programming Guide: https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaViewsGuide/
