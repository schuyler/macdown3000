# Translation brief (MacDown 3000, a macOS Markdown editor)

For each locale assigned to you, read `<locale>.todo.json` in this directory. It has:
- `missing`: map of "<Table>::<key>" -> {english, class, context, table, [same_as, note]}
- `glossary`: that locale's existing translations (English -> localized) from the app. Reuse its terminology wherever it applies (e.g. if "Preview" is already translated, use that word).

Write `<locale>.done.json` in this directory: a JSON object mapping each "<Table>::<key>" to the translated string, for EVERY entry in `missing` EXCEPT entries that have `same_as` (skip those; a script copies the parent item's translation).

Rules:
- Translate the UI label's meaning in context. `context` is the menu path (e.g. "View > Zoom In") or the label itself for preference panes. NSMenuItem/NSMenu are menu bar items; NSButtonCell checkboxes/buttons; NSTextFieldCell labels; NSBox section titles.
- For standard macOS menu items (About/Hide/Quit <App>, Services, Hide Others, Show All, Undo, Redo, Cut, Copy, Paste, Select All, Find…, Spelling and Grammar, Substitutions, Transformations, Speech, Enter Full Screen, Minimize, Zoom, Bring All to Front, Window, Help, Open Recent, Clear Menu, Page Setup…, Print…, Close, Save, Save As…, Revert to Saved, etc.) use the exact wording macOS itself uses in that language.
- Keep the ellipsis character "…" where the English has it, and keep "MacDown 3000" untranslated (it's the app name), e.g. "About MacDown 3000" -> translated "About" + "MacDown 3000".
- Leave as-is: "H1"…"H6" (heading-level buttons), "MacDown 3000" alone, "HTML", "PDF", "CSS", "Markdown", "GitHub", "Graphviz", "Mermaid", "MathJax", "TeX", "Prism", and any entry that is purely a product name. Everything else must be translated (not left in English).
- Preference-pane checkbox labels must be concise (no longer than other labels in the glossary of similar meaning); long labels can wrap badly in the narrow pane.
- "Show Sidebar" / "Hide Sidebar": if the glossary has these (from Localizable.strings), use the same wording.
- Output valid JSON, UTF-8, no comments. Do not modify any other file. Do not touch the git repository.
- Use correct native typography (e.g. French « » not needed here; just the label text). No trailing spaces.

When done, report: locales completed, entry counts written, and any entries you were unsure about (with your choice and the alternative).
