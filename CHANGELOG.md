# Changelog

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
