# Implementation Plan: Fix Preview Pane Scroll Jump with MathJax (Issue #325)

## Problem Summary

When MathJax is enabled, every keystroke causes the preview pane to jump to the beginning. The root cause is in `MPDocument.m:1252`:

```objc
if (self.isPreviewReady && [self.currentBaseUrl isEqualTo:baseUrl] && !self.preferences.htmlMathJax && !stylesChanged)
```

The condition `!self.preferences.htmlMathJax` explicitly bypasses the DOM replacement path when MathJax is enabled, falling through to a full WebView reload via `loadHTMLString:baseURL:` (line 1309), which destroys all scroll state.

The DOM replacement JavaScript (lines 1286-1288) **already contains** correct MathJax re-typesetting logic using `MathJax.Hub.Queue` — MathJax's official API for serializing async typesetting. It was simply never reached.

## Implementation Steps

### Step 1: Write Failing Tests (TDD)

Create `/home/user/macdown3000/MacDownTests/MPMathJaxScrollTests.m` with ~11 test cases:

1. `testMathJaxEnabledUsesDOMReplacement` — core behavioral test
2. `testMathJaxDOMReplacementPreservesScrollPosition`
3. `testMathJaxDOMReplacementInvokesReTypesetting` — verifies JS includes `MathJax.Hub.Queue`
4. `testMathJaxDOMReplacementUpdatesHeaderLocations`
5. `testMathJaxDOMReplacementUpdatesWordCount`
6. `testMathJaxStyleChangeForcesFullReload`
7. `testAlreadyRenderingStateManagedCorrectly`
8. `testMathJaxHeightChangeUpdatesHeaderLocations`
9. `testMathJaxDOMReplacementSavesScrollPosition`
10. `testFirstLoadStillUsesFullReload`
11. `testBaseURLChangeStillUsesFullReload`

Follow existing patterns from `MPScrollSyncTests.m` and `MPWordCountUpdateTests.m`.

### Step 2: Core Fix — Remove MathJax Bypass from DOM Replacement Condition

**File:** `MPDocument.m:1252`

Remove `!self.preferences.htmlMathJax` from the condition:

```objc
// Before:
if (self.isPreviewReady && [self.currentBaseUrl isEqualTo:baseUrl] && !self.preferences.htmlMathJax && !stylesChanged)

// After:
if (self.isPreviewReady && [self.currentBaseUrl isEqualTo:baseUrl] && !stylesChanged)
```

Update the comment (lines 1248-1251) to explain the new approach.

### Step 3: Handle MathJax Height Changes (Expanded Scope)

When MathJax renders TeX, document height changes (e.g., fractions are taller than raw TeX). This makes header locations stale.

**Solution:** Use the existing `MPMathJaxListener` callback bridge to trigger `updateHeaderLocations` + `syncScrollers` after MathJax typesetting completes.

Before the `evaluateScript:` call, set up the listener:

```objc
if (self.preferences.htmlMathJax)
{
    MPMathJaxListener *listener = [[MPMathJaxListener alloc] init];
    __weak MPDocument *weakSelf = self;
    [listener addCallback:^{
        [weakSelf updateHeaderLocations];
        if (weakSelf.preferences.editorSyncScrolling)
            [weakSelf syncScrollers];
    } forKey:@"DOMReplacementDone"];
    [self.preview.windowScriptObject setValue:listener forKey:@"MathJaxListener"];
}
```

Update the JavaScript update script to include the callback after MathJax.Hub.Queue:

```javascript
MathJax.Hub.Queue(function(){
    window.scrollTo(0,scrollY);
    if(typeof MathJaxListener!=='undefined'){
        MathJaxListener.invokeCallbackForKey_('DOMReplacementDone');
    }
});
```

### Step 4: Preserve `lastPreviewScrollTop` During DOM Replacement

After the `evaluateScript:` call, save the scroll position:

```objc
self.lastPreviewScrollTop = scrollBefore;
```

For MathJax, this is handled in the MathJax completion callback.

### Step 5: Push and Verify CI

Push to branch and verify tests pass in GitHub Actions.

## Files to Change

| File | Change |
|------|--------|
| `MacDown/Code/Document/MPDocument.m` | Core fix: remove MathJax bypass, add completion listener, update JS, save scroll position |
| `MacDownTests/MPMathJaxScrollTests.m` | New test file (~11 test cases) |

## Files NOT Changed

| File | Reason |
|------|--------|
| `MPRenderer.m` | Pipeline already correctly includes MathJax scripts |
| `MPMathJaxListener.h/.m` | Existing callback mechanism is sufficient |
| `init.js` | Startup hook is for full reloads only; DOM replacement uses `Hub.Queue` |
| `updateHeaderLocations.js` | Unchanged; just called at the right time |

## Risks & Mitigations

1. **Rapid typing + MathJax typesetting overlap**: `innerHTML` replacement cancels in-progress typesetting; new `Hub.Queue` starts fresh. Correct behavior.
2. **MathJax fails to load**: `typeof MathJaxListener!=='undefined'` guard prevents errors. `scrollTo` still restores position. Acceptable degradation.
3. **`windowScriptObject` lifecycle**: Persists across DOM replacements; safe to overwrite.
4. **Thread safety**: All code runs on main thread. No issues.
5. **First load**: Still uses full reload path (when `isPreviewReady` is NO). Unchanged and correct.
6. **Performance**: DOM replacement is faster than full reload. Net improvement.
