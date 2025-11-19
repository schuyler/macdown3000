# MacDown Feature Guide

Welcome to **MacDown**, a powerful Markdown editor for *macOS*.

## Introduction

MacDown is an [open source](https://github.com/MacDownApp/macdown) Markdown editor that supports:

- **GFM** (GitHub Flavored Markdown)
- Syntax highlighting
- Live preview
- ~~Proprietary formats~~ Standard Markdown only

---

## Code Examples

Here's a simple JavaScript function:

```javascript
function calculateSum(a, b) {
    return a + b;
}
```

You can also write Python:

```python
def greet(name):
    print(f"Hello, {name}!")
```

Inline code like `const x = 42;` is also supported.

## Feature Comparison

| Feature | MacDown | Other Editors |
| :------ | :-----: | ------------: |
| GFM Support | **Yes** | Varies |
| Open Source | Yes | Some |
| macOS Native | Yes | No |
| Price | Free | $10-50 |

## Task List

Development progress:

- [x] Basic Markdown rendering
- [x] Syntax highlighting
- [ ] Plugin system
- [ ] Cloud sync
  - [x] Research options
  - [ ] Implement sync
  - [ ] Add conflict resolution

## Advanced Features

### Nested Lists and Quotes

> Here's what users are saying:
>
> 1. "Great editor!" - User A
> 2. "Love the simplicity" - User B
>    - Fast rendering
>    - Clean interface
>    - **Native performance**

### Images and Links

Check out the logo: ![MacDown Logo](https://macdown.example.com/logo.png)

Visit our website at <https://macdown.example.com>.

### Complex Nesting

1. **Installation Steps**

   First, download from the website:

   ```bash
   curl -O https://example.com/macdown.dmg
   ```

   Then follow these substeps:
   - Open the DMG file
   - Drag to Applications
     - If prompted, enter password
     - Wait for copy to complete
   - Launch MacDown

2. **Configuration**

   > **Note**: You can customize settings in Preferences.

   - [ ] Set default theme
   - [x] Enable auto-save
   - [ ] Configure shortcuts

---

## Contact

Email us at <support@macdown.example.com> or open an issue on [GitHub][gh].

[gh]: https://github.com/MacDownApp/macdown "MacDown on GitHub"

**Happy writing!** *Made with MacDown*
