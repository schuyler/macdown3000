# Changes

## Add "Start in preview mode" preference

Adds a General preferences checkbox that hides the editor pane on every new window launch, so the app always opens in viewer-only mode.

### Files changed

**`MacDown/Code/Preferences/MPPreferences.h`**
- Added `@property (assign) BOOL layoutStartViewerOnly`
- Defaults to `NO` (both panes visible) via standard `NSUserDefaults` BOOL default

**`MacDown/Code/Document/MPDocument.m`**
- In `windowControllerDidLoadNib`, after all setup in the deferred main-queue block, dispatch an additional `dispatch_async` to call `toggleSplitterCollapsingEditorPane:YES` when `layoutStartViewerOnly` is set
- The extra dispatch deferral ensures Auto Layout has completed its first pass before the toggle runs, so `editorVisible` correctly returns `YES` and the editor is collapsed rather than accidentally expanded
- Reuses the existing toggle method so `previousSplitRatio` is correctly initialized before collapsing, keeping the "Show Editor" menu item functional

**`MacDown/Localization/Base.lproj/MPGeneralPreferencesViewController.xib`**
- Extended outer view height 269 → 289 and Behavior box height 175 → 195
- Added checkbox button "Start in preview mode" bound to `self.preferences.layoutStartViewerOnly`
- Removed old `UZT` ("Automatically create files") bottom anchor and rebuilt vertical chain: `WVd → UZT → new button → box bottom`

**`MacDown/Code/Preferences/MPPreferences.m`**
- Added `@dynamic layoutStartViewerOnly` so PAPreferences routes the property through NSUserDefaults; without this the compiler synthesizes a plain ivar and the value is never persisted
