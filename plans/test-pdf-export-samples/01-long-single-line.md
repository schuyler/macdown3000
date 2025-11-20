# Long Code Line Test

This tests a very long line in a code block:

```
const veryLongVariableName = "This is an extremely long string that would normally overflow and get truncated in PDF exports without proper wrapping: Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
```

## Expected Result

The long code line should wrap to multiple lines in the PDF export with no horizontal scrollbar and all text visible.
