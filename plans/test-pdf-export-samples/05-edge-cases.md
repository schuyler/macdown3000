# Edge Cases

## Very long URL in code block
```
https://example.com/this/is/a/very/long/url/path/that/continues/for/quite/some/time/and/should/wrap/properly/in/the/pdf/export?with=query&parameters=too&more=stuff
```

## Code without spaces (worst case for wrapping)
```
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

## Mixed tabs and spaces
```python
def test():
	print("tab character here")
        print("spaces here")
	print("another very long line with tab that should wrap: Lorem ipsum dolor sit amet consectetur")
```

## Empty code block
```
```

## Single character repeated
```
xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## Expected Results

- URLs should break at slashes or query parameters
- Text without spaces should force break at container edge
- Tabs should be preserved, wrapping should still work
- Empty blocks shouldn't cause errors
- Single-character strings should break appropriately
