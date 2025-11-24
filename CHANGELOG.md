# Changelog

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
