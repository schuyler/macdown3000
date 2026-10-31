# #653 Localization coverage for every localized xib

## Requirements (posted on issue #653)
1. (stated) Every titled control and menu item in each localized xib has an entry in every bundled table for that xib; a control added without translations fails a test. AC: the #639 coverage test runs over every xib in Base.lproj, reading keys from the xib at run time, and checks every bundled table for every key.
2. (stated) The gaps found are filled with translations. AC: the test passes; new entries are translated, not English, except product names and the like (MacDown, Markdown, HTML, PDF, CSS; also the H1–H6 heading buttons in MPDocument).
3. (stated) ru-RU stays identical to uk.
4. (inferred) A submenu's own title (an exported <menu> element) uses its parent menu item's translation when its English is the same as the parent item's; otherwise (e.g. "Spelling" under "Spelling and Grammar", and the top-level "Main Menu") it is translated on its own.
5. (inferred, out of scope) existing entries whose value is the English text (~265); a locale's missing whole table (#654).

## Design
### Test (MacDownTests/MPLocalizationContentTests.m)
- Reuse `-titledKeysInBaseXIB:` (added by #639: elements with id + non-empty title -> `<id>.title`; segmentedCell segment labels -> `<id>.ibShadowedLabels[i]`).
- New `-testEveryLocalizedXIBTableCoversEveryTitledControl`: list `*.xib` in the source tree's MacDown/Localization/Base.lproj (path from __FILE__, as #639). For each xib name: count the source tree's `MacDown/Localization/*.lproj/<name>.strings` files and the bundled ones (resourcePath/*.lproj/<name>.strings); assert the counts are equal (a table on disk but not registered in the project is not bundled) and > 0; for each bundled table assert every key is present (message: locale, table, key, English). A table that exists (on disk or bundled) but parses to nil or an empty dictionary FAILS (XCTAssertNotNil / count > 0 with the locale and table in the message) — never skipped: ar has three 0-byte tables (MainMenu, MPDocument, MPExportPanelAccessoryViewController). Assert at least 8 xibs were checked.
- testUkrainianCoversMenuAndDialogStrings asserts uk MainMenu has 53 entries; filling it is intended, so that assertion becomes the Base MainMenu key count (124) — derived from the xib via the helper, not a literal.
- The existing #639 test (Rendering pane, plus not-English check on three keys) stays.

### Filling
- A script (scratch, not committed) lists, per locale, every missing key with English text, class, context (menu path such as "View > Zoom In", or the pane), and a glossary of that locale's existing translations. ru-RU is skipped (copied from uk afterwards). Counts: ar 135 (MainMenu.strings is an empty file), da 115, fi 108, uk 79, sv 76, is 54, sk 46, ko-KR 46, et 42, tr 30, it-IT 24, fr 16, zh-Hant 14, nine locales at 10 (cs, da-DK, de, es, ja, nb-NO, nl-NL, pt-BR, zh-Hans); ar's 135 covers its three empty tables, he 2, hi 2.
- Translations are produced per locale group by implementer subagents into JSON (not into the repo), following macOS's standard menu terminology for that language and the glossary; submenu <menu> titles copy the parent item's translation when the English matches, else are translated on their own; Editor-pane checkbox labels are kept concise (the #659 fit test, with #530's 3% margin, applies to them); items that are product names / H1–H6 may stay as-is.
- An insert script appends entries in ibtool's format (`/* Class = "NSMenuItem"; title = "Zoom In"; ObjectID = "zIn-01-ABC"; */` + `"zIn-01-ABC.title" = "…";`), escaping quotes/backslashes; for an empty file it writes all entries. Then ru-RU.lproj/<table>.strings := copy of uk for every table.
- Review: an independent reviewer checks each locale group's translations for wrong meaning (important) before insertion is accepted; the implementation gate then reviews the whole diff + test.
