# CSS Specificity Issue - Visual Explanation

## What MacDown Generates

```html
<pre><code class="language-python">
def very_long_function_name(...)
</code></pre>
```

## How CSS Rules Apply

### ❌ Current Situation (BROKEN)

```
HTML Element: <pre><code>

┌─────────────────────────────────────────────────────────┐
│ Base CSS (screen)                                       │
├─────────────────────────────────────────────────────────┤
│ pre { overflow: auto; }                    [0-0-1]      │
│ pre code { white-space: pre; }             [0-0-2] ⭐   │
│ code { white-space: nowrap; }              [0-0-1]      │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ @media print CSS                                        │
├─────────────────────────────────────────────────────────┤
│ pre { white-space: pre-wrap !important; }  [0-0-1] +!   │
│ code { white-space: pre-wrap !important; } [0-0-1] +!   │
│ ⚠️  MISSING: pre code { ... }                           │
└─────────────────────────────────────────────────────────┘

Result for <code> inside <pre>:
  - "pre code { white-space: pre; }" wins (highest specificity!)
  - Print rules don't apply
  - Code doesn't wrap
  - PDF gets clipped ❌
```

### ✅ Fixed Situation (WORKING)

```
HTML Element: <pre><code>

┌─────────────────────────────────────────────────────────┐
│ Base CSS (screen)                                       │
├─────────────────────────────────────────────────────────┤
│ pre { overflow: auto; }                    [0-0-1]      │
│ pre code { white-space: pre; }             [0-0-2]      │
│ code { white-space: nowrap; }              [0-0-1]      │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ @media print CSS                                        │
├─────────────────────────────────────────────────────────┤
│ pre { white-space: pre-wrap !important; }  [0-0-1] +!   │
│ pre code { white-space: pre-wrap !important; } [0-0-2] +! ⭐ │
│ code { white-space: pre-wrap !important; } [0-0-1] +!   │
└─────────────────────────────────────────────────────────┘

Result for <code> inside <pre>:
  - "pre code { white-space: pre-wrap !important; }" wins
  - Print rules APPLY
  - Code wraps
  - PDF looks perfect ✅
```

## CSS Specificity Reminder

CSS Specificity format: [inline-style, IDs, classes/attributes, elements]

- `code` → [0-0-1] (1 element)
- `pre` → [0-0-1] (1 element)
- `pre code` → [0-0-2] (2 elements) **MORE SPECIFIC**

**Higher specificity always wins, even against `!important` from lower specificity!**

## The 3-Line Fix

Add this to EVERY `@media print` section in all 6 CSS files:

```css
@media print {
    /* existing rules... */
    pre {
        white-space: pre-wrap !important;
        overflow-wrap: break-word;
    }

    /* ADD THIS: */
    pre code, pre tt {
        white-space: pre-wrap !important;
        overflow-wrap: break-word;
    }

    code, tt {
        white-space: pre-wrap !important;
        overflow-wrap: break-word;
    }
}
```

## Files to Fix

1. `/home/user/macdown3000/MacDown/Resources/Styles/Clearness.css`
2. `/home/user/macdown3000/MacDown/Resources/Styles/Clearness Dark.css`
3. `/home/user/macdown3000/MacDown/Resources/Styles/GitHub.css`
4. `/home/user/macdown3000/MacDown/Resources/Styles/GitHub2.css`
5. `/home/user/macdown3000/MacDown/Resources/Styles/Solarized (Light).css`
6. `/home/user/macdown3000/MacDown/Resources/Styles/Solarized (Dark).css`

---

## Update: Alternative Implementation (2025-11-20)

The specificity analysis in this document is **correct**, but the implementation approach changed.

**Instead of modifying 6 individual theme files**, a universal solution was implemented:

- **Created:** `MacDown/Resources/Extensions/print.css` (single file for all themes)
- **Modified:** `MPRenderer.m` to load print.css LAST in stylesheet cascade
- **Result:** Universal fix without per-theme modifications

This provides the same specificity override (`pre code` = 0-0-2 + `!important`) but through a single maintainable file instead of 6 separate modifications.

See `ISSUE_28_INVESTIGATION.md` for complete resolution details.
