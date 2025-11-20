# Square Brackets in Code (Issue #37)

## Test Case 1: TypeScript index signature

```typescript
interface MyType {
  [key: string]: any;
}
```

## Test Case 2: JavaScript array access

```javascript
const value = array[index];
const obj = {
  [computed]: 'value'
};
```

## Test Case 3: Multiple bracket patterns

```typescript
type Dict = {
  [id: number]: string;
}

interface Config {
  [key: string]: {
    [nested: string]: boolean;
  };
}
```

## Test Case 4: Inline code with brackets

Here's an example: `array[0]` and `obj[key]` should work.

## Test Case 5: Python dictionary syntax

```python
my_dict = {
    "key": "value"
}
result = my_dict["key"]
```
