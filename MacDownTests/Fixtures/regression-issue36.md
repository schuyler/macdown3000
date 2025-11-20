# Code Blocks Without Blank Lines (Issue #36)

## Test Case 1: Fenced code block immediately after text
Here is some code:
```
function test() {
  return true;
}
```

## Test Case 2: Multiple code blocks in sequence
First block:
```javascript
const x = 42;
```
Second block:
```python
y = 100
```

## Test Case 3: Code block with proper blank line (works correctly)

This should work:

```
function working() {
  return 'yes';
}
```

## Test Case 4: Code block in list without blank line
Steps to follow:
- First step
- Run this code:
```
npm install
```
- Last step
