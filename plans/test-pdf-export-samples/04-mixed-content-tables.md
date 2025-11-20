# Mixed Content Test

| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| `short` | `anotherShortExample()` | Normal text |
| `veryLongCodeInTableCell_thisCouldCauseProblems_ifNotHandledCorrectly()` | Text | More |

```javascript
// Comment with a very long line: This is a comment that goes on and on and on and should wrap properly
const obj = { property1: "value", property2: "another value", property3: "yet another value that makes this line very long" };
```

## Expected Result

Table cells with long code should wrap appropriately, code blocks below tables should render correctly, and no layout breakage should occur.
