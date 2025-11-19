# Link Tests

## Inline Links

This is an [inline link](https://example.com).

This is a [link with title](https://example.com "Example Title").

This is a [link to a path](/path/to/page).

## Reference Links

This is a [reference link][ref1].

This is another [reference link][ref2].

This uses [implicit reference].

[ref1]: https://example.com
[ref2]: https://example.org "Reference with Title"
[implicit reference]: https://implicit.example.com

## Edge Cases

[Link at start](https://start.com) of line.

End of line [has a link](https://end.com).

Multiple [first link](https://first.com) and [second link](https://second.com) in one line.

A [link with **bold** text](https://bold.com) inside.
