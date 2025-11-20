# Comprehensive PDF Export Test

This file combines all test scenarios for thorough testing of code block overflow handling in PDF exports.

---

## Test 1: Long Single Line

```
const veryLongVariableName = "This is an extremely long string that would normally overflow and get truncated in PDF exports without proper wrapping: Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
```

---

## Test 2: Multiple Long Lines

```python
def some_function_with_a_very_long_name_that_demonstrates_wrapping(parameter1, parameter2, parameter3, parameter4, parameter5):
    result = "This is another very long string that should wrap properly in the PDF export without being cut off at the edge"
    another_long_variable = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua ut enim ad minim veniam"
    return result
```

---

## Test 3: Inline Code

This paragraph contains inline code that is quite long: `veryLongFunctionName(withManyParameters, andMoreParameters, evenMoreParameters, keepingGoing, almostDone, thisIsReallyLong)` and it should wrap within the paragraph.

Another test: `https://github.com/schuyler/macdown3000/this/is/a/very/long/url/that/should/wrap/properly/in/pdf/exports/without/breaking/the/layout`

---

## Test 4: Table with Long Code

| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| `short` | `anotherShortExample()` | Normal text |
| `veryLongCodeInTableCell_thisCouldCauseProblems_ifNotHandledCorrectly()` | Text | More |

---

## Test 5: JavaScript Code Block

```javascript
// Comment with a very long line: This is a comment that goes on and on and on and should wrap properly
const obj = { property1: "value", property2: "another value", property3: "yet another value that makes this line very long" };
const anotherLongStatement = someFunction(parameter1, parameter2, parameter3, parameter4, parameter5, parameter6, parameter7);
```

---

## Test 6: URL in Code Block

```
https://example.com/this/is/a/very/long/url/path/that/continues/for/quite/some/time/and/should/wrap/properly/in/the/pdf/export?with=query&parameters=too&more=stuff&even=more&parameters=here
```

---

## Test 7: No Spaces (Worst Case)

```
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

---

## Test 8: Normal Code (Regression Test)

This should look normal and not have unnecessary wrapping:

```python
def hello():
    print("Hello, World!")
    return True
```

This `inline code` is short and should be fine.

---

## Expected Behaviors

✅ All long lines wrap without being cut off
✅ No horizontal scrollbar in PDF
✅ Monospace font preserved
✅ Indentation maintained where possible
✅ Normal/short code looks professional
✅ Inline code wraps within paragraphs
✅ Tables don't break layout
