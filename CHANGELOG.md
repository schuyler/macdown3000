# Changelog

## [Unreleased]

### Added

- Show a live word/character/character-no-spaces count for the current editor selection in the count widget, reverting to document totals when nothing is selected (#452)

### Security

- Restrict auto-created link targets to the current document's folder to prevent unauthorized file creation (#386)

### Fixed

- Fix spurious "changed by another application" save conflicts and save failures on remote/FUSE-mounted volumes (e.g. SSHFS) by bypassing NSDocument's atomic temp-file-swap save for non-local destinations and writing directly instead; this should also stop the "does not support permanent version storage" prompt from appearing for those documents, since it's raised from the same code path (#371) -- thanks @gurple for the report!
- Fix the Insert Table toolbar button doing nothing when the editor pane had focus, and corrupting the document when clicked repeatedly (a second table was inserted inside the first table's cell); every click now inserts a clean, well-separated table regardless of which pane has focus (#278) -- thanks @rcuisnier for the report!
- Fix auto-reload silently breaking after an external editor's atomic save by making the local-volume watcher check fall back to the parent directory when the file is transiently missing; also guard resource-file watchers against remote volumes and tear down any prior watcher before re-arming (#478)
- Fix the Preview pane still auto-scrolling toward the editor when typing after Sync Panes was turned off mid-session; toggling Sync Panes now takes effect immediately (settling the panes on disable, re-syncing on enable) without needing to reopen the document (#441) -- thanks @gregwillits!
- Fix blank preview when opening saved or externally-originated documents: the real document file is no longer used as the preview's base resource, which WebKit on macOS 26 can silently refuse to load (e.g. files with the execute bit set by sync clients like OneDrive, or stale TCC/provenance state) (#431, #405) -- thanks @maskedspitz, @songjianbupt, and @craigrodger for the diagnosis!
- Improve render-path responsiveness: single-pass word/character counting, cached body-extraction regex, and bounded renderer polling with cancellation (#388)
- Restrict auto-created link targets to the current document's folder scope (#388)
- Fix line enumeration in scroll sync header scanning to handle `\r\n` and bare `\r` line endings (#388)

<!-- rc-temp -->
## [3000.0.7-rc.3] - 2026-07-01

Third release candidate. Fixes Quick Look extension entitlements stripped by release re-signing, toolbar buttons not dispatching when the editor has focus, checkbox label clipping in localized preference panes, toolbar redraws after switching preference panes, and spurious save conflicts on remote volumes. Also completes localization of the selection count widget.

### Added

- Add localized selection count strings to all locale files (#452, PR #501) -- thanks @Telamonster for the report!
- Wire Quick Look extension into Xcode build (#284, PR #477) -- thanks @caius for the report!
- Add GitHub Dark Default editor theme (PR #465) -- thanks @sks3691 for the contribution!
- Add editor invisible character toggle (#43, PR #462) -- thanks @yusufm for the contribution!
- Add File menu autosave toggle (#301, PR #459) -- thanks @Xylopyrographer for the report! thanks @yusufm for the contribution!
- Add insert table toolbar action (#278, PR #420) -- thanks @rcuisnier for the report! thanks @yusufm for the contribution!
- Add Selection character/word count (#452, PR #460) -- thanks @Telamonster for the report!
- Persist preview-only startup mode (PR #383) -- thanks @yusufm for the contribution!
- Emit slug-based heading IDs for anchor link navigation (#429, PR #430) -- thanks @falcon-enoc for the report and the contribution!

### Changed

- Dynamic preferences pane sizing for localized strings (#397, PR #481) -- thanks @rcuisnier for the report!
- Color HTML in default editor themes (#443, PR #458) -- thanks @gregwillits for the report!
- Support uppercase task list checkboxes (#369, PR #410) -- thanks @gino-santerre-telus for the report! thanks @yusufm for the contribution!
- Hide unparsable YAML front matter (#307, PR #413) -- thanks @yusufm for the contribution!
- Make the toolbar fully delegate-driven so Flexible Space can be dropped (#313, PR #473) -- thanks @gregwillits for the report!
- Extend wide-table horizontal scrolling to all themes (screen only) (#432, PR #468) -- thanks @dafi for the report!
- Widen HTML preferences pane to fit theme controls (#397, PR #467) -- thanks @rcuisnier for the report!
- Sort editor theme and rendering CSS preference menus (PR #404)
- Improve render-path responsiveness (PR #388) -- thanks @yusufm for the contribution!

### Fixed

- Fix Quick Look extension entitlements stripped by release signing (#284, PR #494) -- thanks @caius for the report!
- Fix toolbar buttons not dispatching when editor has focus (#278, PR #496) -- thanks @rcuisnier for the report!
- Fix checkbox label clipping in localized preference panes (#397, PR #498) -- thanks @rcuisnier for the report!
- Force toolbar redraw after preference pane switch (PR #500)
- Bypass atomic safe-save on remote volumes to prevent spurious save conflicts and the "does not support permanent version storage" prompt on SSHFS and similar mounts (#371, PR #502) -- thanks @gurple for the report!
- Harden file watching against transient paths and remote volumes (#478, PR #492)
- Fix Insert Table toolbar regression: button now works regardless of which pane has focus, repeated clicks no longer nest tables (#278, PR #483) -- thanks @rcuisnier for the report!
- Fix crash on empty Markdown headings from slug-based heading IDs (#479, PR #482) -- thanks @Telamonster for the report!
- Skip file watchers on remote volumes (#371, PR #424) -- thanks @gurple for the report! thanks @yusufm for the contribution!
- Re-highlight editor after preview checkbox toggle (#376, PR #480)
- Fix blank preview for documents with execute bit set (#431, #405, PR #454) -- thanks @maskedspitz and @b2sc for the reports!
- Never use the document file as the preview base URL (#405, #431, PR #456) -- thanks @b2sc and @maskedspitz for the reports!
- Normalize CRLF line endings on file load (#382, PR #398) -- thanks @Ariaflux for the report!
- Cache-bust style/theme CSS on preview reload (#318, PR #474) -- thanks @gregwillits for the report!
- Restore natural table width and horizontal scrolling (#432, PR #440) -- thanks @dafi for the report! thanks @samqbush for the contribution!
- Keep editor and preview panes in sync on large files (#436, PR #464) -- thanks @KingMob for the report!
- Honor Sync Panes toggle mid-session (#441, PR #463) -- thanks @gregwillits for the report!
- Clear editor highlighting on reload (#378, PR #415) -- thanks @yusufm for the contribution!
- Re-initialize task list handlers after DOM replacement (#376, PR #400)
- Strip grey background from printed output (#387, PR #403) -- thanks @richb-hanover for the report!
- Preserve custom Prism theme filename case (#315, PR #416) -- thanks @gregwillits for the report! thanks @yusufm for the contribution!
- Mirror drag-collapse ratio on pane swap (#380, PR #414) -- thanks @yusufm for the contribution!
- Fix preference pane layout for localized text wrapping (#397, PR #461) -- thanks @rcuisnier for the report!
- Fix Settings panel layout clipping and field overlap (#397, PR #399) -- thanks @rcuisnier for the report!
- Fix EXC_BAD_ACCESS when clicking grouped toolbar buttons (PR #393) -- thanks @yusufm for the contribution!
- Guard nil-group and out-of-bounds index in grouped toolbar item selection (#394, PR #396)
- Fix entitlements loss during app re-signing (#302, PR #472) -- thanks @whispersnowleopard for the report!
- Open only the help document on first launch (#428, PR #445) -- thanks @mundijr for the report! thanks @1waterrj for the contribution!
- Fix Xcode runtime warnings (PR #401) -- thanks @yusufm for the contribution!

### Security

- Harden Quick Look preview sandbox (PR #385) -- thanks @yusufm for the contribution!
- Harden preview script boundaries (PR #384) -- thanks @yusufm for the contribution!
- Restrict auto-created link targets (PR #386) -- thanks @yusufm for the contribution!

### Documentation

- Fix and clarify line break example in help.md (PR #434) -- thanks @mjonss for the contribution!

### Infrastructure

- Regression coverage for uppercase task list checkboxes, preview image rendering, and navigation completion; @primer/css and sass tooling bumps in the GitHub-style generator; CI and /review tooling updates; release-train RC process; website update for 3000.0.6; remove gh CLI install machinery from canned workflows.
<!-- /rc-temp -->

## [3000.0.6] - 2026-04-18

This release rebuilds scroll sync around an ownership model that eliminates timing-based race conditions, and fixes several user-reported bugs with preview rendering, Quick Look, and diagram support. The deep dive into the long history of the editor / preview panel scroll synchronization took about a day of persistent work. Hopefully it was worth it!

### Fixed

- Fix view menu "Hide/Restore" pane labels not updating (#377, #310) -- thanks @gregwillits for the report!
- Fix scroll sync jump during typing and remaining sync gaps (#342)
- Fix preview rendering stuck blank on new documents (#358) -- thanks @rcuisnier for the report!
- Fix multiple Mermaid/Graphviz diagrams not rendering (#331, #332) -- thanks @rcuisnier and @gino-santerre-telus for the reports!
- Fix stale image preview after external atomic save (#349) -- thanks @bh18-nuff for the report!
- Fix Quick Look extension: blank preview, missing entitlements (#367)
- Fix word count throttle for smoother updates (#294) -- thanks @benel for the report!
- Fix preference panels to be resizable with centered content (#361, #362) -- thanks @rcuisnier for the reports!

### Added

- Live-edit Graphviz re-rendering via MutationObserver (#332)

## [3000.0.5] - 2026-04-07

Highlights include Quick Look support for Markdown files, new preview themes for GitHub Dark, Google Docs, and Gmail, improved file watching, and resolutions for many user-reported issues.

### Security

- Fix CVE-2019-12138 (directory traversal) and CVE-2019-12173 (RCE via app bundle links) in the preview pane's file:// navigation handler (#356, #351) — reported by @jhengels

### Fixed

- Fix file watcher dropping after atomic save by external editors (#354) — reported by @btsai, contributed by @BenCello
- Fix editor scroll jump during typing at end of long documents (#343)
- Fix Mermaid diagrams not rendering during live preview (#333) — reported by @rcuisnier
- Fix preview scroll jump when MathJax is enabled (#330) — reported by @causalcat
- Fix PDF/print margins to respect Page Setup and remove double margins (#329)
- Fix style reload not updating Preview pane (#328) — reported by @gregwillits
- Fix main thread crash in userDefaultsDidChange (#323)
- Fix split view not maintaining 1:1 ratio on resize or maximize (#321) — reported by @5T33Z0
- Fix Help Menu document window sizing behavior (#319) — reported by @gregwillits
- Fix dollar-sign math highlighting being applied unconditionally (#317)
- Fix editor pane menu item not toggling to Restore (#316) — reported by @gregwillits
- Fix "Move To" failing on macOS Sequoia with ViewBridge error 14 (#303) — reported by @whispersnowleopard
- Fix word count not updating during typing (#296) — reported by @benel
- Disable intra-word emphasis by default to prevent underscore false positives (#295) — reported by @pringshia

### Added

- GitHub2 (Dark) preview theme (#350) — contributed by @withakay
- Google Docs and Gmail preview themes (#348) — contributed by @petems
- Watch local CSS/JS resources and refresh Preview automatically on change (#327)
- Auto-save preference to control automatic document saving (#326)
- Support for user-provided Prism syntax highlighting themes (#324) — reported by @gregwillits
- Allow flexible space, space, and separator items in toolbar customization (#322) — reported by @gregwillits
- Quick Look preview extension for Markdown files (#299) — reported by @caius
- Complete i18n/localization coverage for shell utility strings (#298)
- Hide YAML front matter in Preview instead of rendering as an HTML table (#312) — reported by @whispersnowleopard
- Automatic file reload when a document is modified by an external editor (#297) — reported by @btsai

### Changed

- FileURLInlining code cleanup using more idiomatic Objective-C (#304) — contributed by @wltb

## [3000.0.4] - 2026-01-25

This release focuses on editor stability and usability fixes, addressing scroll jumping issues, window positioning, text substitution bugs, and Markdown rendering edge cases.

### Fixed

- Fix smart quote substitution causing unwanted characters (#289, #285) -- thanks @5T33Z0 for the report!
- Fix editor jumping when typing at end of long documents (#288, #282) -- thanks @rcuisnier for the report!
- Fix preview scroll jumping during editing (#282) -- thanks @rcuisnier for the report!
- Fix new document windows opening at bottom-left (#286) -- thanks @mbinkhorst for the contribution!
- Fix Graphviz and Mermaid button positioning in Compilation Settings (#280, #277) -- thanks @rcuisnier for the report!
- Fix adjacent shortcut-style links not rendering correctly (#275, #25)
- Fix text substitution settings not persisting (#263) -- thanks @5T33Z0 for the report!

## [3000.0.3] - 2026-01-15

This release graduates from beta with bug fixes for export, code block rendering, and text substitutions, adds a new dark preview theme, and introduces interactive checkbox support.

### Added

- Add GitHub Tomorrow dark preview theme (#273, #106) -- based on @elsiehupp's contribution to MacDown
- Enable interactive checkbox support by default (#270, #269) -- thanks @rosmur for the feature request!

### Fixed

- Fix export/print when Preview Pane is hidden (#274, #16)
- Fix fenced code block rendering without preceding blank line (#272, #36)
- Fix square brackets vanishing in code blocks (#272, #37)
- Disable text substitutions by default for all users (#268, #263) -- thanks @5T33Z0 for the report!

### Changed

- Refactor file inlining for drag-and-drop (#248) -- thanks @wltb for the contribution!

### Documentation

- Add documentation for the table of contents token feature (#265) -- thanks @sbeitzel for the contribution!

## [3000.0.3-beta.1] - 2026-01-09

This beta release upgrades Mermaid to v11.12.1, adds bidirectional scroll sync, and includes several bug fixes for Markdown rendering, drag-and-drop, and settings persistence.

### Added

- Upgrade Mermaid to v11.12.1 for improved flowchart rendering (#262, #35)
- Add bidirectional scroll sync between preview and editor (#261, #258) -- thanks @dadvir!
- Code-sign the macdown CLI binary (#239, #238) -- thanks @henryhchchc!

### Fixed

- Fix lists not rendering immediately after paragraphs (#260, #254) -- thanks @justinabrahms!
- Fix tab characters causing unexpected line breaks near line end (#256)
- Fix persistence of Substitutions and Spelling settings (#252)
- Fix drag-and-drop for images and mixed file types (#240, #244, #247) -- thanks @wltb!

### Documentation

- Update README for 2026 (#246) -- thanks @brianzelip!

## [3000.0.2] - 2025-12-30

This release removes remote image loading from the built-in help file, fixes broken localization for German and Slovak, and expands unit test coverage.

MacDown 3000 is now available via Homebrew. Try it!

```bash
brew install --cask macdown-3000
```

### Fixed

- Import help.md images locally to eliminate external d.pr network requests (#232) -- thanks @robbyt!
- Fix broken German (DE) and Slovak (SK) localizations (#230) -- thanks @emsspree!

### Infrastructure

- Expand unit test coverage with notification, lifecycle, and edge case tests (#233, #235)
- Add workflow to submit PRs to homebrew-cask on release (#225, #226)

## [3000.0.1] - 2025-12-20

This patch release fixes three bugs affecting the editor and preview pane.

### Fixed

- Fix CSS style and syntax highlighting theme changes not applying in Preview pane (#219, #221) -- thanks @kojika!
- Fix copy-paste regression in editor (#214, #220) -- thanks @sveinbjornt!
- Add smart paste linkification for selected text (#222, #223)

## [3000.0.0] - 2025-12-13

This release finalizes the MacDown 3000 platform with expanded internationalization support and improved clipboard handling for Markdown content.

### Added

- Add complete localizations for Russian, Arabic, Hindi, Ukrainian, and Hebrew preferences (#212)

### Fixed

- Add markdown UTType when copying from editor to improve clipboard compatibility (#208)

## [3000.0.0-beta.3] - 2025-12-07

This release addresses several bug fixes including a critical issue where both editor and preview panes could be hidden simultaneously, improvements to the preview pane reload behavior, and removes the deprecated plugin system.

### Fixed

- Fix hiding both editor and preview panes bug (#207, #23)
- Fix preview pane Reload to re-render instead of loading raw markdown (#204)
- Fix download button to directly download DMG file (#202)
- Fix documentation typos and add missing Oxford commas (#206)
- Fix version number in About pane and Credits.rtf formatting

### Removed

- Remove deprecated plugin system (#205)

## [3000.0.0-beta.2] - 2025-11-26

### Fixed

- Fix line breaking in HTML exports (#191)
- Fix horizontal rule regex edge cases and fragile header detection (#185)
- Fix Markdown preferences display for Korean locale (#176)
- Fix buffer overflow in toolbar initialization - Intel Mac crash (#178)
- Fix hang-on-launch issue on macOS Sequoia (#170)

## [3000.0.0-beta.1] - 2025-11-24

### Fixed

- **Hang on launch for macOS Sequoia** - Fixed initialization deadlock affecting macOS 15.x (#169, #170)
- **Intel Mac toolbar crash** - Fixed buffer overflow in toolbar initialization (#178)
- **French localization errors** - Corrected translation issues in French language files (#172)

### Infrastructure

- **Intel CI testing** - Added dedicated Intel Mac testing with diagnostic logging (#177)
- **Unsigned artifact preservation** - Retained unsigned builds in dry run workflow (#171)

## [3000.0.0-beta.0] - 2025-11-21

### Major Changes

- **Rebranded as MacDown 3000** - New identity and versioning scheme for the modernized Markdown editor
- **Apple Silicon support** - Native arm64 builds with full compatibility alongside Intel x86_64 builds
- **Modernized project infrastructure** - Updated to Xcode standards with improved CI/CD automation

### Fixed

- **Preview pane flickering** - Fixed by reverting WebCache disabling approach (#9, #109)
- **Editor/preview pane sync issues** - Fixed loss of sync caused by image loading delays (#39, #145)
- **Mermaid gantt diagram rendering** - Corrected diagram rendering output (#18, #151)
- **Open Recent menu on macOS Sonoma** - Restored functionality on recent macOS versions (#32, #119)
- **Shell utility installation on macOS Sonoma** - Fixed installation process compatibility (#38, #120)
- **Code block overflow in PDF exports** - Improved handling and documented remaining issues (#125, #130)
- **Compiler warnings** - Resolved all compiler warnings for cleaner builds

### Changed

- **Updated application namespace** - Changed from original MacDown NSID to new namespace (#128)
- **Upgraded dependencies** - Updated CocoaPods, Hoedown, Prism, and other core dependencies (#132)
- **Strikethrough syntax** - Enabled by default for better Markdown compatibility (#45, #102)

### Removed

- **Travis CI** - Replaced with GitHub Actions
- **Broken Transifex references** - Cleaned up obsolete translation service integrations (#127)
- **Sparkle auto-updates** - Temporarily disabled pending modernization

### Known Issues

- **Hoedown parser limitations** - Documented edge cases in Markdown parsing that users should be aware of

### Infrastructure

- **GitHub Actions CI/CD** - Complete migration from Travis CI with matrix testing for multiple macOS versions
- **Regression tests** - Tests for known Hoedown parser limitations and issue #39 edge cases (#148, #149)
- **File I/O and document lifecycle tests** - Enhanced testing coverage for document operations (#90, #97)
- **Unit test coverage** - Expanded test suite with rendering, document I/O, scroll sync, and syntax highlighting tests
- **Code coverage reporting** - Integrated code coverage metrics in CI/CD pipeline (#114)
- **Release automation** - Fully automated release process with git-tag-only versioning (#155)
- **Code signing automation** - Added automated code signing and release builds (#69)
- **Developer setup script** - Streamlined local development environment setup (#71)
- **Updated npm dependencies** (#71)

---

## Previous Releases

For historical changelog information about MacDown versions 0.6.x through 0.8.0d71, please refer to the original [MacDown repository](https://github.com/MacDownApp/macdown).
