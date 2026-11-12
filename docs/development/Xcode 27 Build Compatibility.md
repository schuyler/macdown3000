# Xcode 27 Build Compatibility

| Document information | Details |
|---|---|
| Document status | Development documentation |
| Created | 2026-11-12 |
| Last updated | 2026-11-12 |
| Status | Development branch |
| Branch | `fix/xcode-27-build` |
| Environment | macOS, Apple Silicon M4 |
| Xcode version | 27.2 (Build 27B52) |
| Purpose | Document the changes required to build MacDown 3000 successfully with Xcode 27.2. |
---

## 1. Overview

The original project checkout did not build successfully with Xcode 27.2.

The initial build exposed several compatibility issues involving:

- Generation of the PEG Markdown Highlight parser.
- Xcode's user script sandboxing.
- Build settings and project configuration migrated by Xcode.

The changes documented here address those issues while retaining the existing application source code.

The work is intended to establish a reproducible development environment before investigating further changes to the application's MathJax integration.

No application functionality or application source code has been intentionally modified as part of this work.

## 2. Development Environment

The following environment was used for the successful build.

| Component | Version / Configuration |
|---|---|
| Architecture | Apple Silicon (arm64) |
| Xcode | 27.2 |
| Xcode build | 27B52 |
| Workspace | `MacDown 3000.xcworkspace` |
| Application scheme | `MacDown` |
| UI test scheme | `MacDownUITests` |
| Deployment target | macOS 14.6 |

The project should be opened using `MacDown 3000.xcworkspace`, rather than the `.xcodeproj` file, because the workspace includes the CocoaPods dependencies.

## 3. Changes Made

### 3.1 PEG Markdown Highlight parser generation

**Problem**

The Xcode project references:

`Dependency/peg-markdown-highlight/pmh_parser.c`

However, this file is generated and is not included in the repository as a tracked source file.

The parser must be generated before Xcode attempts to compile the application sources.

The initial build failed because the generated parser file was unavailable.

**Solution**

A new Run Script build phase was added to the Xcode project.

Build phase name:

`Generate PEG Markdown Parser`

Script:

```bash
#!/bin/bash
set -e

make -C "$SRCROOT/Dependency/peg-markdown-highlight"
```

The build phase is positioned immediately before `Compile Sources`.

The following input files are declared:

```text
$(SRCROOT)/Dependency/peg-markdown-highlight/pmh_grammar.leg
$(SRCROOT)/Dependency/peg-markdown-highlight/pmh_parser_head.c
$(SRCROOT)/Dependency/peg-markdown-highlight/pmh_parser_foot.c
$(SRCROOT)/Dependency/peg-markdown-highlight/tools/combine_parser_files.sh
```

The declared output is:

```text
$(SRCROOT)/Dependency/peg-markdown-highlight/pmh_parser.c
```

The output path points to the actual generated file in the source tree.

**Verification**

The generated `pmh_parser.c` file was deleted manually and the project was subsequently built successfully. This demonstrated that the build phase could regenerate the missing parser.

A subsequent ordinary build also completed successfully.

**Implementation reference**

This approach is consistent with the parser-generation solution used in upstream MacDown PR #1385, adapted to the MacDown 3000 project structure.

### 3.2 Xcode user script sandboxing

**Problem**

Xcode 27 introduced build failures associated with scripts writing files into locations that were not permitted by the user script sandbox.

Two examples were encountered:

1. The `MacDownCore` target attempted to create resources under the framework's build output.
2. The `FETCH PRISM RESOURCES` build phase attempted to copy Prism resources into the application source tree.

The affected scripts perform file-system operations required by the existing build process.

**Solution**

The following build targets have user script sandboxing disabled:

- `MacDown`
- `MacDownCore`
- `MacDownQuickLook`

The setting is:

```text
ENABLE_USER_SCRIPT_SANDBOXING = NO
```

The setting is applied to the relevant Debug and Release configurations.

This permits the existing build scripts to perform their required file-system operations.

**Security and maintenance consideration**

Disabling user script sandboxing reduces the restrictions applied to build scripts. This should be reviewed before an upstream contribution.

A longer-term alternative would be to modify the scripts so that their outputs are written into appropriate derived build directories and declare their inputs and outputs explicitly.

### 3.3 Xcode project migration

The project was opened and updated using Xcode 27.2.

This resulted in additional project configuration changes, including:

- Xcode project format and migration metadata.
- Scheme and workspace configuration updates.
- Build configuration updates.
- Compiler warning settings.
- Module verification settings.
- Build-system configuration changes.

These changes are recorded in:

```text
MacDown 3000.xcodeproj/project.pbxproj
MacDown 3000.xcodeproj/xcshareddata/xcschemes/MacDown.xcscheme
MacDown 3000.xcodeproj/xcshareddata/xcschemes/MacDownUITests.xcscheme
MacDown 3000.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings
```

The changes should be reviewed to ensure that unrelated automatic migration changes are not included unnecessarily in an upstream pull request.

### 3.4 macOS deployment target

The application deployment target was changed to:

```text
macOS 14.6
```

This represents the minimum operating system version selected for this development configuration.

**Important compatibility consideration**

The repository README currently advertises macOS 11.0 (Big Sur) as the minimum supported operating system.

Changing the deployment target to 14.6 therefore changes the project's advertised compatibility if applied consistently to all relevant targets and release configurations.

This decision needs maintainer review before the change is submitted upstream. The README, release configuration and CI build matrix may also need to be considered.

## 4. Development Setup

The repository's existing development setup should be followed.

From the repository root:

```bash
git submodule update --init
bundle install
bundle exec pod install
```

The PEG parser can also be generated manually:

```bash
make -C Dependency/peg-markdown-highlight
```

Open the workspace:

```bash
open "MacDown 3000.xcworkspace"
```

The application should be built using the `MacDown` scheme and the `My Mac` destination.

## 5. Build Verification

### 5.1 Application build

A clean build was completed successfully after the changes were applied.

The PEG parser was also successfully regenerated after its generated output was manually removed.

The following command can be used to reproduce an application build from the terminal:

```bash
xcodebuild \
  -workspace "MacDown 3000.xcworkspace" \
  -scheme "MacDown" \
  -destination 'platform=macOS,arch=arm64' \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build
```

The explicit sandboxing override is included for reproducibility. The project also contains target-level sandboxing settings.

### 5.2 UI tests

The UI test suite was executed using:

```bash
xcodebuild \
  -workspace "MacDown 3000.xcworkspace" \
  -scheme "MacDownUITests" \
  -destination 'platform=macOS,arch=arm64' \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  test
```

Results from the recorded test run:

| Test | Result |
|---|---|
| `testAppLaunchesWithWindow` | Failed |
| `testCanTypeInEditor` | Passed |
| `testEditorTextViewExists` | Passed |
| `testPreviewPaneExists` | Passed |

Three of the four tests passed.

The remaining test failed because XCTest could not terminate an existing MacDown application process during test setup.

The process was associated with Xcode's LLDB debugging process. It was subsequently terminated manually.

The test suite has not yet been rerun to establish whether this resolves the failure.

**Assessment:** The UI test failure has not been demonstrated to be an application functionality regression. It remains an outstanding test-environment issue.

### 5.3 Verification summary

| Verification | Result |
|---|---|
| PEG parser generation | Successful |
| Clean application build | Successful |
| Subsequent application build | Successful |
| UI test suite | 3 passed, 1 failed |
| Git whitespace validation | Passed |

## 6. Known Issues and Outstanding Work

The following items should be considered before submitting an upstream contribution.

1. **UI test termination failure:** Rerun the UI test suite after clearing the stale application process.
2. **Deployment target:** Confirm whether macOS 14.6 is an acceptable minimum, given the project's existing macOS 11.0 compatibility statement.
3. **Script sandboxing:** Review whether the affected scripts can be adapted to work with sandboxing enabled.
4. **Parser build dependencies:** Review whether the parser build phase should declare additional inputs, including the Makefile and PEG generator sources, to ensure correct incremental rebuilding when those files change.
5. **Xcode migration changes:** Review the project file diff and remove unrelated automatic migration changes where appropriate.
6. **CI compatibility:** Confirm that the updated project builds in the repository's GitHub Actions environment and on the supported architectures.

## 7. Scope and Non-Goals

This work is limited to Xcode build compatibility.

It does not include:

- Changes to Markdown parsing or rendering.
- Changes to the editor or preview functionality.
- Changes to the MathJax implementation.
- Changes to application features.
- Changes to third-party dependency versions.

The MathJax upgrade is a separate investigation and should be developed independently of these build configuration changes.

## 8. Git and Contribution Notes

The work is maintained on the separate branch:

```text
fix/xcode-27-build
```

The changes should remain separate from `main` until reviewed.

Before submitting a pull request:

- Review the complete project configuration diff.
- Confirm the intended macOS deployment target with the maintainers.
- Verify the parser build phase and its dependencies.
- Test the application build and relevant automated tests.
- Check that no generated files, local caches or unrelated development environment changes have been committed.

The repository's contribution guidance recommends checking for an existing issue before submitting a new issue or contribution.

---

## 9. Conclusion

The project has been successfully built using Xcode 27.2 after addressing the generated PEG parser and build-script sandboxing issues.

The changes provide a working baseline for further development on the MacDown 3000 project.

The outstanding UI test issue and deployment-target compatibility decision should be reviewed separately. Once these matters have been resolved, the build compatibility changes can be considered for an upstream contribution.