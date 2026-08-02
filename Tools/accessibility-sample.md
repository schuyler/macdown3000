# Accessibility sample

Test document for `Tools/macdown-ax-dump.swift` (Issue #545). Keep it short —
the dump prints every text run it finds, so a long document buries the signal.

Open this in MacDown 3000 with the preview pane visible, then run:

    ./Tools/macdown-ax-dump.swift

Plain text for a baseline, then **bold text**, then *italic text*, then
_underlined text_, then ~~struck text~~, then plain text again.

Note that MacDown enables Hoedown's underline extension, so `_this_` renders as
`<u>` rather than `<em>` — that is why italic above uses asterisks and
underline uses underscores.

Each formatting run on its own, in case surrounding text confuses the runs:

- **bold**
- *italic*
- _underline_
- ~~strikethrough~~
- ***bold italic***

## Heading level two

Headings already announce correctly according to the issue reporter, so they
serve as a control: whatever the dump shows for this line is what a *working*
attribute looks like in this app.
