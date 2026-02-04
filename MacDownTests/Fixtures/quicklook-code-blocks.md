# Code Blocks Test for Quick Look

## Fenced Code Block (No Language)

```
plain code block
no syntax highlighting
```

## Python

```python
def hello():
    print("Hello, World!")

if __name__ == "__main__":
    hello()
```

## JavaScript

```javascript
function greet(name) {
    console.log(`Hello, ${name}!`);
}

greet('World');
```

## Objective-C

```objc
@interface MyClass : NSObject
@property (nonatomic, copy) NSString *name;
- (void)sayHello;
@end

@implementation MyClass
- (void)sayHello {
    NSLog(@"Hello, %@!", self.name);
}
@end
```

## Shell

```bash
#!/bin/bash
echo "Hello from shell"
ls -la
```

## JSON

```json
{
    "name": "MacDown 3000",
    "version": "3000.0.4",
    "features": ["markdown", "preview", "quicklook"]
}
```

## Inline Code

Use `NSString` for strings and `NSArray` for arrays.
