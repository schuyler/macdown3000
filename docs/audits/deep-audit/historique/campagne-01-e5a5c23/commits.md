# Commits de la reprise

Chaque correction de production a son commit autonome. Les commits de tests et de preuve sont identifiés par leur préfixe. Un commit ancien peut être remplacé par une correction ultérieure après une nouvelle preuve : notamment le matching PDF par occurrences, invalidé par un essai réel avec ordre CSS inversé ; il ne doit pas être considéré comme validé dans la version finale.

La justification et les contrôles réels sont dans les notes de `preuves/`. Suite finale sur les dernières sources : 1427 tests, zéro échec, et builds propres universels Debug/Release verts ; l’acceptation UI reste bloquée avant le premier test. Aucun push effectué.

| Commit | Objet |
| --- | --- |
| `2979bce` | fix(clipboard): reject empty strings before URL parsing (EU-07) |
| `0b4b432` | fix(markdown): require complete front matter delimiters (EU-08) |
| `f666683` | fix(javascript): preserve UTF-8 and reject unserializable values (EU-03) |
| `6fde0c6` | fix(clipboard): validate text clipping property list types (EU-10) |
| `9209797` | fix(document): preserve existing files when creating documents (EU-06) |
| `7bf00de` | fix(url): resolve final symlinks before checking document scope (EU-01) |
| `1ae7a16` | fix(preferences): release copied Core Foundation values (EU-09) |
| `2a3a7f6` | fix(files): isolate temporary documents and mapped assets (EU-05, UI-007) |
| `1e80c08` | fix(editor): keep unindent selections inside the edited text (EU-04) |
| `eb849ab` | fix(editor): preserve cursor when removing heading markers (EU-04) |
| `5cde2ef` | fix(editor): remove complete list and quote markers (EU-04) |
| `9d2c77a` | fix(resources): resolve HTML URLs and preserve query fragments (EU-11) |
| `f0fa5dc` | fix(preferences): isolate migration reads and prevent late writes (UI-003) |
| `d253e70` | fix(preferences): preserve migration markers from newer versions (UI-004) |
| `5104c51` | fix(terminal): repair dangling installation symlinks (UI-001) |
| `5bd2af0` | fix(terminal): refuse uninstalling commands owned by others (UI-002) |
| `e34d661` | fix(terminal): stop callbacks after controller destruction (UI-005) |
| `858097c` | fix(sidebar): refuse opening Markdown-named directories (UI-006) |
| `89e008b` | fix(preferences): enable diagrams independently of highlighting (UI-008) |
| `1b9ef4f` | fix(localization): use cardinal plural rules for Slavic counters (UI-014) |
| `2627ac2` | fix(mermaid): render rejection messages as text |
| `e220c1c` | fix(mermaid): rerender replaced DOM after pending diagrams |
| `8bb8822` | fix(scroll): distinguish inline images from standalone references |
| `f65ca66` | fix(watchers): invalidate delayed recovery after removal (EU-02) |
| `b378de0` | test(menu): check declared shortcuts independently of keyboard layout |
| `04cd794` | test(preferences): assert migration writes in the persistent domain |
| `9dc2295` | test(sidebar): select the actual Markdown-named directory row |
| `9a6bab4` | fix(tools): restore golden regeneration sources on every failure |
| `5042773` | fix(build): generate styles atomically and prepare Sass dependencies |
| `dbb5d41` | fix(tools): propagate failed and missing test runs |
| `b9550a4` | fix(tools): reject successful runners that execute zero tests (RB-01) |
| `7071925` | fix(cli): consume delayed pipes and preserve literal file paths |
| `b813569` | fix(website): preserve literal metadata and find latest prerelease (EU-20) |
| `fc67731` | fix(build): regenerate and safely encode version headers |
| `3e57d13` | fix(build): initialize missing processed bundle version keys |
| `2d14dda` | fix(build): quote version strings in PlistBuddy commands (RB-02) |
| `0dc530f` | fix(ci): pass release and build inputs as literal environment data (EU-18) |
| `2a29df5` | fix(ci): share process-aware smoke launch and migration checks (EU-19) |
| `84275b6` | fix(yaml): validate graph ownership and stream read/write contracts (EU-13) |
| `7e965df` | fix(yaml): populate and compare collection keys by value |
| `9e43bf2` | fix(yaml): preserve serialization failure in string writer |
| `d3ce004` | test(terminal): exercise discovery completion after controller release |
| `b597a80` | docs(audit): preserve previous evidence and record resumed review |
| `a6fbe93` | fix(pdf): resolve links using explicit visible DOM occurrences |
| `717f203` | test(pdf): print only page glyphs and verify persisted destinations |
| `553c94f` | fix(peg): grow grammar buffers and stacks without fixed limits (EU-16) |
| `8ddf577` | fix(peg): allocate complete AST nodes (RP01) |
| `b973d05` | fix(peg): fail atomically when rebuilding generated parsers (EU-17) |
| `d84c4f0` | fix(styles): bound repeated rules and trim empty values safely (EU-15) |
| `fb1916a` | fix(highlighting): discard stale parses and reset active styles (EU-14) |
| `8d4833c` | fix(editor): preserve Markdown labels and pasted URL parentheses (EU-12) |
| `14dc5bc` | fix(editor): convert character ranges to glyph ranges for layout (EU-12) |
| `d7378c6` | fix(styles): include Primer tokens for standalone Markdown (RR-01) |
| `bde9a0c` | fix(build): resolve system frameworks through the selected SDK |
| `e70fd19` | test(preferences): run terminal installer regressions in Xcode |
| `e96dfac` | fix(quicklook): complete only the current preview navigation |
| `c2dd35f` | fix(build): generate shared resources before app and Quick Look packaging |
| `502c10d` | fix(print): retain completion delegates and forward Cocoa arguments |
| `116a276` | fix(document): preserve Markdown before its editor loads |
| `daf2a23` | fix(document): report invalid UTF-8 read errors |
| `a2e67b6` | fix(markdown): share context-aware preprocessing and map rendered tasks to source |
| `ad2ce74` | fix(renderer): publish only the latest asynchronous render without spinning |
| `ec92284` | fix(renderer): render changes to MathJax preferences |
| `fc6cf2f` | fix(renderer): escape code block information attributes |
| `f93bcb7` | fix(renderer): trim list paragraphs without crossing buffer bounds |
| `7f3cd6d` | fix(markdown): generate unique matching heading and TOC destinations |
| `d668304` | fix(markdown): recognize fences consistently across quote and info contexts |
| `a43f757` | fix(renderer): preserve embedded NUL bytes in body and TOC |
| `714cfd5` | fix(renderer): keep TOC dollars and backslashes literal |
| `a859d86` | fix(markdown): reject overflowing numeric header entities |
| `f90cc3b` | fix(print): preserve dark theme headings on white paper |
| `ea136da` | fix(localization): package five missing translation domains |
| `7aba894` | fix(document): cancel stale file callbacks after close and Save As |
| `87de279` | fix(preview): refresh the checkbox token during DOM replacement |
| `a976430` | fix(export): reserve PDF export before showing its save panel |
| `f74d97f` | fix(document): keep self-save protection through overlapping saves |
| `4210f5c` | fix(export): wait for the requested preview before consuming output |
| `727682c` | fix(preview): coalesce resource callbacks after HTML publication |
| `f49e6a3` | fix(preview): reload changed scripts and diagram dependencies |
| `845d901` | fix(export): write HTML atomically and report failures |
| `37d410e` | fix(scroll): bound alignment memory for large documents |
| `7e00e29` | fix(scroll): clamp viewport positions and reject missing geometry |
| `f84e39a` | fix(editor): render underline correctly with its extension disabled |
| `4e72643` | fix(editor): preserve selected text deletion around paired characters |
| `fd7081b` | fix(editor): map Smart Home character positions to glyph ranges |
| `a46418b` | fix(editor): enable footnote parsing when the preference is enabled |
| `6e8d0db` | fix(quicklook): grant read-only access to application preferences |
| `c194023` | fix(localization): label French speech actions as reading |
| `d5ecd3d` | fix(localization): use French bold label for strong formatting |
| `1c98aa0` | fix(localization): preserve Mermaid product name in preferences |
| `0c68600` | fix(localization): restore Estonian link menu title |
| `1425a85` | fix(localization): label Korean recent documents menu |
| `6fee6aa` | fix(localization): label Korean find and replace action |
| `8de6c25` | fix(localization): describe indentation actions in Dutch |
| `789e376` | fix(localization): correct simplified Chinese unordered list label |
| `4bcca64` | fix(localization): correct traditional Chinese bold label |
| `be1cdf9` | docs(help): explain front matter exclusion from rendered body |
| `07e9ebb` | docs(help): correct editor theme file extension |
| `da6bc87` | docs(quicklook): describe actual script-free rendering contract |
| `c91b9f9` | fix(build): synchronize Quick Look versions before signing |
| `1d9fe2b` | test(document): verify PDF panel reservation and cancellation |
| `8c80554` | test(document): verify overlapping saves preserve external reload guard |
| `21828e9` | test(preview): verify head script refresh and retained JavaScript state |
| `a841445` | test(preview): verify resource coalescing and stale watcher rejection |
| `40d1bf6` | test(export): verify HTML write errors preserve existing files |
| `bde22d1` | test(ci): run native build and resource contract regressions |
| `97f699c` | docs(audit): record corrections and outstanding delivery gates |
| `0c80850` | fix(quicklook): resolve and read shared user styles in sandbox |
| `e2845a7` | fix(pdf): preserve native link geometry and original print appearance |
| `24b2e48` | test(export): consume completed Mermaid diagrams with real WebKit |
| `bae35a9` | fix(pdf): publish original directly when no internal anchors exist |
| `984b8b3` | fix(preview): restore local document after foreign navigation |
