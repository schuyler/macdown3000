# Quick Look Extension - Xcode Project Setup

This document describes the Xcode project changes needed to build the Quick Look extension for MacDown 3000 (Issue #284).

## New Targets to Create

### 1. MacDownCore Framework

Create a new **macOS Framework** target named `MacDownCore`.

**Bundle Identifier:** `app.macdown.macdown3000.MacDownCore`

**Source Files to Include:**
- `MacDownCore/MacDownCore.h`
- `MacDownCore/MPQuickLookRenderer.h`
- `MacDownCore/MPQuickLookRenderer.m`
- `MacDownCore/MPQuickLookPreferences.h`
- `MacDownCore/MPQuickLookPreferences.m`

**Dependencies:**
- hoedown (via CocoaPods)
- handlebars-objc (via CocoaPods)

**Build Settings:**
- `MACOSX_DEPLOYMENT_TARGET`: 11.0
- `DEFINES_MODULE`: YES
- `PRODUCT_NAME`: MacDownCore
- `INFOPLIST_FILE`: Create a basic framework Info.plist

**Public Headers:**
- `MacDownCore.h`
- `MPQuickLookRenderer.h`
- `MPQuickLookPreferences.h`

### 2. MacDownQuickLook Extension

Create a new **macOS Quick Look Preview Extension** target named `MacDownQuickLook`.

**Bundle Identifier:** `app.macdown.macdown3000.QuickLook`

**Source Files:**
- `MacDownQuickLook/PreviewViewController.h`
- `MacDownQuickLook/PreviewViewController.m`
- `MacDownQuickLook/Info.plist`

**Dependencies:**
- MacDownCore.framework (link to the framework)
- WebKit.framework
- Quartz.framework

**Build Settings:**
- `MACOSX_DEPLOYMENT_TARGET`: 11.0
- `CODE_SIGN_ENTITLEMENTS`: `MacDownQuickLook/MacDownQuickLook.entitlements`
- `INFOPLIST_FILE`: `MacDownQuickLook/Info.plist`
- `PRODUCT_BUNDLE_IDENTIFIER`: `app.macdown.macdown3000.QuickLook`
- `LD_RUNPATH_SEARCH_PATHS`: `@executable_path/../Frameworks @executable_path/../../../../Frameworks`

**Embed Framework:**
The MacDownCore.framework should be embedded in the extension.

### 3. Update MacDownTests Target

Add the following header search paths to MacDownTests:
- `$(SRCROOT)/MacDownCore`

This allows tests to import the Quick Look renderer and preferences classes.

## Resource Files

The MacDownCore framework needs access to these resources:

1. **Styles/** - CSS stylesheets for markdown rendering
2. **Prism/** - Syntax highlighting components
   - `Prism/components/` - Language-specific JS files
   - `Prism/themes/` - Theme CSS files

These can either be:
- Copied into the framework bundle
- Or accessed from the main app bundle via bundle path resolution

## Embedding the Extension

The Quick Look extension must be embedded in the main MacDown application:

1. In the main MacDown target, add MacDownQuickLook to **Embed App Extensions**
2. Ensure the extension is signed with the same team as the main app

## CocoaPods Setup

After updating the Podfile, run:

```bash
bundle exec pod install
```

This will set up the dependencies for the new targets.

## Testing

The test files (`MPQuickLookRendererTests.m` and `MPQuickLookPreferencesTests.m`) should be added to the MacDownTests target.

The test fixtures (`quicklook-*.md`) should be added to the test bundle's Fixtures directory.

## Verification

After setup, verify:

1. MacDownCore framework builds successfully
2. MacDownQuickLook extension builds and links to MacDownCore
3. MacDown app builds and embeds both the framework and extension
4. Tests compile and can be run (they should fail until implementations are complete)
