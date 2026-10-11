# Nouvelle lecture intégrale Document — 9 octobre 2026

Lecture repartie de zéro sur les fichiers finaux, après les corrections confirmées. Pas de validation héritée de la première passe. Lecture et analyse finales terminées après le dernier correctif de sauvegarde. Tests ciblés verts ; validation globale native/UI encore attendue, donc aucune certification anticipée de livraison.

## Journal de lecture

| Fichier | Plages réellement lues sans troncature | Analyse |
| --- | --- | --- |
| MPDocument.m | 1–600, 601–1200, 1201–1800, 1801–2400, 2401–3000, 3001–3600, 3601–4200, 4201–4800, 4801–5400, 5401–5650, 5651–5850, 5851–6050, 6051–6556 | Helpers texte/source, instantané CSSOM et session PDF/restore, préférences/flags Hoedown, signature ressources, panneau de recherche et états document. Réexamen complet des branches try/catch de la session PDF, pseudo-sélecteurs, restauration attributs/règles et propriété des objets. Puis propriétés/contrats privés, completion de rendu bornée par génération, fence scanner, accesseurs et undo scripting, titre des compteurs, initialisation nib/observers et installation sidebar jusqu’à visibilité. Puis sidebar sync/ouverture, reload/fermeture, sauvegardes coordonnées/localité, sérialisation UTF-8, impression/validation UI, commandes clavier, délégations WebKit/navigation/find et continuation bornée par génération. Le défaut d’ordre de sauvegarde relevé dans la lecture précédente est corrigé et réexaminé intégralement ici ; Ressources/render/cache rapides vs reload, token propriétaire, reprise MathJax/print, notifications sync et géométrie reading progress, KVO, exports/PDF et commandes toolbar (dont nouveaux sept callbacks renderer) entièrement relus. Puis insertion table/bornes, actions source et split, rendu différé/export, setup editor/font/zoom, classificateur de références approximatif, alignement LCS borné 8 MiB + fallback monotone et début syncScrollers. L’alignement supporte explicitement les différences regex/DOM ; aucune preuve de nouvelle mutation incorrecte. Fin du fichier intégralement relue : sync/cursor/reverse, base URL/navigation/exécutables, compteur throttlé, callbacks impression, draft/flush/fermeture, installation mapping (occurrences/probes/whitespace bornés), transaction UTF-16/source, conversions/blocs/style/math, queue commune et bridge, checkbox + watchers/reload + zoom. Dans la lecture précédente avant correction, l’appel 5401–6000 avait une sortie tronquée et avait été repris intégralement. La dernière lecture après correction utilise directement des plages plus petites, toutes reçues sans troncature. Nouvelle relecture complète répétée après correction de l’ordre flush/newline : flush synchronisé main avant mutation source et bookkeeping, refus préserve draft/texte/fichier. Toutes les autres fonctions et branches ont de nouveau été lues, sans raccourci par diff. |
| MPDocumentLifecycleTests.m | 1–500, 501–1000, 1001–1350, 1351–1600, 1601–1850, 1851–2200, 2201–2450, 2451–2687 | Infrastructures HTTP/spy/panel/print, dirty/undo, fichiers/encodages/type/autosave et reload/gates relus. Quelques tests historiques ne vérifient que le filesystem ou contiennent une tautologie (preservesVersions) ; ils ne sont pas utilisés pour démontrer nos invariants corrigés. Tous les parcours suivants ont été relus : préférences/IME/backspace, save timers, ressources/signature, find, erreurs/sélection, source mapping UTF-16 et styles mixtes, longs parcours popup/toolbar/restore, reading progress, wrapping/Prism, coalescence watchers, export/diagrams/HTTP, identité auteur, markers/Setext/wrappers, queue frontières et nouveau test draft/newline, incluant refus de draft périmé sans mutations et vraie écriture des données modifiées. Fixtures et assertions vérifiées dans leur contexte de classe/implémentation complet. |

## Invariants et points à fermer

- Source Markdown seule autorité ; correspondances DOM/source, token et plages vérifiés avant écriture. Tokens = fraîcheur et provenance, pas autorisation contre JS déjà exécuté dans le contexte.
- Publication PDF échoue sans publier quand snapshot/parse/génération divergent ; restauration réversible CSSOM/attributs même en exception.
- Une correction par commit ; tests réels et flags de renderer alignés sur préférences. Les anciennes fixtures de tâche sans flags ne prouvent pas un défaut de consommation.
- Commandes source Texte normal/H1–H6 : dépendance Autocomplete en correction par agent renderer, correction confirmée et tests source ciblés verts avec l’oracle renderer ; sept callbacks migrés, ancienne API retirée par l’agent renderer.
- Queue popup/toolbar unifiée après rouge réel, frontières stale-token/action/valeur vertes en WebView réel, sans consommation de la continuation légitime.

## Empreintes de la dernière lecture intégrale après correctif

- `MacDown/Code/Document/MPDocument.m` : 6556 lignes, SHA-256 `f2a130c74ff27e646ebe6ec665285e756539aef5442b26b43f99ea66ab7d9fc6`.
- `MacDownTests/MPDocumentLifecycleTests.m` : 2687 lignes, SHA-256 `6b4bfa45679e7bac3d6c84915fab75b7720ec8baa6bae2a4cb5f48a26f649c27`.

## Registre exhaustif des méthodes Objective-C relues

Ce registre est un index des lectures et de l’analyse, pas une validation automatisée. Toutes les branches de ces corps ont été examinées dans les plages ci-dessus.

| Ligne | Signature |
| --- | --- |
| 311 | `- (NSString *)absoluteBaseURLString` |
| 325 | `- (NSScrollView *)enclosingScrollView` |
| 334 | `- (int)extensionFlags` |
| 364 | `- (int)rendererFlags` |
| 409 | `- (void)sendEvent:(NSEvent *)event` |
| 417 | `- (BOOL)performKeyEquivalent:(NSEvent *)event` |
| 440 | `- (void)cancelOperation:(id)sender` |
| 798 | `- (MPPreferences *)preferences` |
| 803 | `- (NSString *)markdown` |
| 808 | `- (void)setMarkdown:(NSString *)markdown` |
| 839 | `- (NSString *)html` |
| 844 | `- (BOOL)toolbarVisible` |
| 849 | `- (BOOL)previewVisible` |
| 854 | `- (BOOL)editorVisible` |
| 859 | `- (BOOL)needsHtml` |
| 868 | `- (NSString *)wordCountTitleForKey:(NSString *)key number:(NSUInteger)value` |
| 876 | `- (void)applyWordsTitle:(NSUInteger)value selected:(BOOL)selected` |
| 883 | `- (void)applyCharactersTitle:(NSUInteger)value selected:(BOOL)selected` |
| 891 | `- (void)applyCharactersNoSpacesTitle:(NSUInteger)value selected:(BOOL)selected` |
| 902 | `- (void)setTotalWords:(NSUInteger)value` |
| 909 | `- (void)setTotalCharacters:(NSUInteger)value` |
| 916 | `- (void)setTotalCharactersNoSpaces:(NSUInteger)value` |
| 923 | `- (void)setAutosaveName:(NSString *)autosaveName` |
| 931 | `- (NSUInteger)mathJaxRenderGeneration` |
| 938 | `- (instancetype)init` |
| 965 | `- (NSString *)windowNibName` |
| 970 | `- (void)windowControllerDidLoadNib:(NSWindowController *)controller` |
| 1111 | `- (void)registerSharedPreferenceObservers` |
| 1122 | `- (void)unregisterSharedPreferenceObservers` |
| 1131 | `+ (NSRange)selectionRange:(NSRange)range clampedToLength:(NSUInteger)length` |
| 1149 | `- (void)setWorkspaceRootURL:(NSURL *)workspaceRootURL` |
| 1155 | `- (void)installFolderSidebarForController:(NSWindowController *)controller` |
| 1221 | `- (void)outerSplitDidResize:(NSNotification *)note` |
| 1237 | `- (BOOL)isSidebarVisible` |
| 1245 | `- (void)showSidebarPane` |
| 1274 | `- (void)hideSidebarPane` |
| 1284 | `- (IBAction)toggleFolderSidebar:(id)sender` |
| 1301 | `- (void)sidebarSyncDidChange:(NSNotification *)note` |
| 1326 | `+ (MPDocument *)openDocumentForFileURL:(NSURL *)url` |
| 1336 | `+ (NSError *)sidebarOpenErrorForError:(NSError *)error URL:(NSURL *)url` |
| 1359 | `- (void)presentSidebarOpenError:(NSError *)error forURL:(NSURL *)url` |
| 1366 | `- (void)folderSidebar:(MPFolderSidebarViewController *)sidebar didActivateFileURL:(NSURL *)url` |
| 1420 | `- (void)reloadFromLoadedString` |
| 1491 | `- (void)close` |
| 1570 | `+ (BOOL)autosavesInPlace` |
| 1575 | `+ (NSArray *)writableTypes` |
| 1580 | `- (BOOL)isDocumentEdited` |
| 1591 | `- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError *__autoreleasing *)outError` |
| 1658 | `- (BOOL)writeSafelyToURL:(NSURL *)url ofType:(NSString *)typeName forSaveOperation:(NSSaveOperationType)saveOperation error:(NSError *__autoreleasing *)outError` |
| 1699 | `- (BOOL)shouldBypassSafeSaveForURL:(NSURL *)url` |
| 1704 | `- (BOOL)flushPreviewEditorForSaveWithError:(NSError **)outError` |
| 1717 | `- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError` |
| 1724 | `- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError` |
| 1744 | `- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel` |
| 1793 | `- (NSPrintInfo *)printInfo` |
| 1804 | `- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)printSettings error:(NSError *__autoreleasing *)e` |
| 1823 | `- (void)printDocumentWithSettings:(NSDictionary *)printSettings showPrintPanel:(BOOL)showPrintPanel delegate:(id)delegate didPrintSelector:(SEL)selector contextInfo:(void *)contextInfo` |
| 1847 | `- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item` |
| 1941 | `- (void)splitViewDidResizeSubviews:(NSNotification *)notification` |
| 1972 | `- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview` |
| 1980 | `- (NSUndoManager *)undoManagerForTextView:(NSTextView *)textView` |
| 1985 | `- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector` |
| 2000 | `- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)str` |
| 2031 | `- (BOOL)textViewShouldInsertTab:(NSTextView *)textView` |
| 2046 | `- (BOOL)textViewShouldInsertBacktab:(NSTextView *)textView` |
| 2052 | `- (BOOL)textViewShouldInsertNewline:(NSTextView *)textView` |
| 2068 | `- (BOOL)textViewShouldDeleteBackward:(NSTextView *)textView` |
| 2086 | `- (BOOL)textViewShouldMoveToLeftEndOfLine:(NSTextView *)textView` |
| 2118 | `- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)dataSource` |
| 2135 | `- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame` |
| 2158 | `- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame` |
| 2166 | `- (void)finishPreviewRender` |
| 2184 | `- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame` |
| 2205 | `- (void)webView:(WebView *)webView decidePolicyForNavigationAction:(NSDictionary *)information request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener` |
| 2282 | `- (BOOL)webView:(WebView *)webView doCommandBySelector:(SEL)selector` |
| 2301 | `- (BOOL)previewHasFindFocus` |
| 2310 | `- (BOOL)validateDocumentFindAction:(NSMenuItem *)item` |
| 2331 | `- (IBAction)performDocumentFindAction:(id)sender` |
| 2339 | `- (void)performPreviewFindAction:(NSTextFinderAction)action` |
| 2412 | `- (void)findPreviewText:(NSSearchField *)field` |
| 2420 | `- (void)findPreviewAdjacent:(NSSegmentedControl *)sender` |
| 2426 | `- (NSUInteger)webView:(WebView *)webView dragDestinationActionMaskForDraggingInfo:(id<NSDraggingInfo>)info` |
| 2432 | `- (NSArray *)webView:(WebView *)sender contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)defaultMenuItems` |
| 2456 | `- (void)reloadPreview:(id)sender` |
| 2465 | `- (BOOL)rendererLoading` |
| 2469 | `- (NSString *)rendererMarkdown:(MPRenderer *)renderer` |
| 2474 | `- (NSString *)rendererHTMLTitle:(MPRenderer *)renderer` |
| 2483 | `- (int)rendererExtensions:(MPRenderer *)renderer` |
| 2488 | `- (BOOL)rendererHasSmartyPants:(MPRenderer *)renderer` |
| 2493 | `- (BOOL)rendererRendersTOC:(MPRenderer *)renderer` |
| 2498 | `- (NSString *)rendererStyleName:(MPRenderer *)renderer` |
| 2503 | `- (BOOL)rendererDetectsFrontMatter:(MPRenderer *)renderer` |
| 2508 | `- (BOOL)rendererWrapsCodeBlocks:(MPRenderer *)renderer` |
| 2513 | `- (BOOL)rendererHasSyntaxHighlighting:(MPRenderer *)renderer` |
| 2518 | `- (BOOL)rendererHasMermaid:(MPRenderer *)renderer` |
| 2523 | `- (BOOL)rendererHasGraphviz:(MPRenderer *)renderer` |
| 2528 | `- (MPCodeBlockAccessoryType)rendererCodeBlockAccesory:(MPRenderer *)renderer` |
| 2533 | `- (BOOL)rendererHasMathJax:(MPRenderer *)renderer` |
| 2538 | `- (NSString *)rendererHighlightingThemeName:(MPRenderer *)renderer` |
| 2543 | `- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html` |
| 2746 | `- (NSURL *)rendererBaseURL:(MPRenderer *)renderer` |
| 2778 | `- (NSURL *)previewSafeBaseURL:(NSURL *)baseURL` |
| 2797 | `- (void)resourceWatcherSet:(MPResourceWatcherSet *)set didDetectChangeAtPath:(NSString *)path` |
| 2822 | `- (void)makeWindowControllers` |
| 2829 | `- (void)editorTextDidChange:(NSNotification *)notification` |
| 2846 | `- (void)editorSelectionDidChange:(NSNotification *)notification` |
| 2892 | `- (void)refreshDocumentWordCountTitles` |
| 2901 | `- (void)userDefaultsDidChange:(NSNotification *)notification` |
| 2940 | `- (void)handleSyncScrollingEnabled` |
| 2962 | `- (void)handleSyncScrollingDisabled` |
| 2974 | `- (void)editorFrameDidChange:(NSNotification *)notification` |
| 2987 | `- (void)willStartLiveScroll:(NSNotification *)notification` |
| 2994 | `-(void)didEndLiveScroll:(NSNotification *)notification` |
| 3002 | `- (void)willStartPreviewLiveScroll:(NSNotification *)notification` |
| 3012 | `- (void)didEndPreviewLiveScroll:(NSNotification *)notification` |
| 3030 | `- (void)refreshHeaderCacheAfterResize` |
| 3040 | `- (void)windowDidEndLiveResize:(NSNotification *)notification` |
| 3048 | `- (void)windowDidChangeFullScreen:(NSNotification *)notification` |
| 3056 | `- (void)editorBoundsDidChange:(NSNotification *)notification` |
| 3071 | `- (void)didRequestEditorReload:(NSNotification *)notification` |
| 3078 | `- (void)didRequestPreviewReload:(NSNotification *)notification` |
| 3085 | `- (void)previewBoundsDidChange:(NSNotification *)notification` |
| 3103 | `- (void)scheduleReadingProgressUpdate` |
| 3112 | `- (void)observeReadingProgressDocumentView` |
| 3128 | `- (void)readingProgressDocumentDidChange:(NSNotification *)notification` |
| 3133 | `- (void)setupReadingProgress` |
| 3185 | `- (void)updateReadingProgress` |
| 3209 | `- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context` |
| 3238 | `- (IBAction)copyHtml:(id)sender` |
| 3256 | `- (IBAction)exportHtml:(id)sender` |
| 3291 | `- (IBAction)exportPdf:(id)sender` |
| 3338 | `- (BOOL)preparePDFAnchorSession` |
| 3365 | `- (void)restorePDFAnchorSession` |
| 3383 | `- (BOOL)PDFExportSnapshotIsCurrent` |
| 3392 | `- (void)publishPDFDocument:(PDFDocument *)document atURL:(NSURL *)url` |
| 3400 | `- (void)postProcessExportedPDFAtURL:(NSURL *)url` |
| 3447 | `- (IBAction)convertToH1:(id)sender` |
| 3454 | `- (IBAction)convertToH2:(id)sender` |
| 3461 | `- (IBAction)convertToH3:(id)sender` |
| 3468 | `- (IBAction)convertToH4:(id)sender` |
| 3475 | `- (IBAction)convertToH5:(id)sender` |
| 3482 | `- (IBAction)convertToH6:(id)sender` |
| 3489 | `- (IBAction)convertToParagraph:(id)sender` |
| 3496 | `- (IBAction)toggleStrong:(id)sender` |
| 3502 | `- (IBAction)toggleEmphasis:(id)sender` |
| 3508 | `- (IBAction)toggleInlineCode:(id)sender` |
| 3514 | `- (IBAction)toggleStrikethrough:(id)sender` |
| 3520 | `- (IBAction)toggleUnderline:(id)sender` |
| 3529 | `- (IBAction)toggleHighlight:(id)sender` |
| 3534 | `- (IBAction)toggleComment:(id)sender` |
| 3539 | `- (IBAction)toggleLink:(id)sender` |
| 3559 | `- (IBAction)toggleImage:(id)sender` |
| 3600 | `+ (NSString *)tableInsertionForContent:(NSString *)content selectedRange:(NSRange)selectedRange replacementRange:(NSRange *)outReplacementRange caretLocation:(NSUInteger *)outCaretLocation` |
| 3668 | `- (IBAction)insertTable:(id)sender` |
| 3697 | `- (IBAction)toggleOrderedList:(id)sender` |
| 3702 | `- (IBAction)toggleUnorderedList:(id)sender` |
| 3708 | `- (IBAction)toggleBlockquote:(id)sender` |
| 3713 | `- (IBAction)indent:(id)sender` |
| 3721 | `- (IBAction)unindent:(id)sender` |
| 3726 | `- (IBAction)insertNewParagraph:(id)sender` |
| 3749 | `- (IBAction)setEditorOneQuarter:(id)sender` |
| 3754 | `- (IBAction)setEditorThreeQuarters:(id)sender` |
| 3759 | `- (IBAction)setEqualSplit:(id)sender` |
| 3764 | `- (IBAction)toggleToolbar:(id)sender` |
| 3769 | `- (IBAction)togglePreviewPane:(id)sender` |
| 3774 | `- (IBAction)toggleEditorPane:(id)sender` |
| 3779 | `- (IBAction)toggleAutoSave:(id)sender` |
| 3785 | `- (IBAction)toggleInvisibleCharacters:(id)sender` |
| 3791 | `- (IBAction)render:(id)sender` |
| 3806 | `- (void)invalidateStyleCaches` |
| 3846 | `- (void)performAfterRender:(void (^)(void))handler` |
| 3870 | `- (void)invokeRenderCompletionHandlers` |
| 3884 | `- (void)toggleSplitterCollapsingEditorPane:(BOOL)forEditorPane` |
| 3922 | `- (void)applyEditorStartInPreviewModePreference` |
| 3943 | `- (void)setupEditor:(NSString *)changedKey` |
| 4086 | `- (void)adjustEditorInsets` |
| 4102 | `- (void)redrawDivider` |
| 4128 | `- (CGFloat)previewScale` |
| 4142 | `- (CGFloat)zoomMultiplier` |
| 4148 | `- (void)setZoomMultiplier:(CGFloat)zoomMultiplier` |
| 4154 | `- (void)scaleWebview` |
| 4163 | `- (NSFont *)zoomedEditorFont` |
| 4172 | `- (void)applyEditorFontAndParagraphStyle` |
| 4203 | `- (IBAction)zoomIn:(id)sender` |
| 4208 | `- (IBAction)zoomOut:(id)sender` |
| 4213 | `- (IBAction)resetZoom:(id)sender` |
| 4218 | `- (void)applyCurrentZoom` |
| 4263 | `-(void) updateHeaderLocations` |
| 4359 | `+ (NSArray<NSNumber *> *)editorReferenceKindsForMarkdown:(NSString *)markdown outLineNumbers:(NSArray<NSNumber *> **)outLineNumbers` |
| 4597 | `+ (void)alignEditorYs:(NSArray<NSNumber *> *)editorYs editorTypes:(NSArray<NSNumber *> *)editorTypes previewYs:(NSArray<NSNumber *> *)previewYs previewTypes:(NSArray<NSNumber *> *)previewTypes alignedEditorYs:(NSArray<NSNumber *> **)outEditorYs alignedPreviewYs:(NSArray<NSNumber *> **)outPreviewYs` |
| 4705 | `- (void)validateHeaderLocationAlignment` |
| 4741 | `- (void)syncScrollers` |
| 4849 | `- (void)syncScrollersToCursor` |
| 4918 | `+ (CGFloat)previewYForCursorY:(CGFloat)cursorDocumentY editorContentHeight:(CGFloat)editorContentHeight editorVisibleHeight:(CGFloat)editorVisibleHeight editorScrollOffsetY:(CGFloat)editorScrollOffsetY previewContentHeight:(CGFloat)previewContentHeight previewVisibleHeight:(CGFloat)previewVisibleHeight editorHeaderLocations:(NSArray<NSNumber *> *)editorHeaderLocations webViewHeaderLocations:(NSArray<NSNumber *> *)webViewHeaderLocations` |
| 5004 | `- (void)syncScrollersReverse` |
| 5094 | `- (void)setSplitViewDividerLocation:(CGFloat)ratio` |
| 5121 | `- (NSString *)presumedFileName` |
| 5154 | `- (void)updateWordCount` |
| 5174 | `- (void)scheduleWordCountUpdate` |
| 5199 | `- (BOOL)isCurrentBaseUrl:(NSURL *)another` |
| 5226 | `- (BOOL)canAutomaticallyCreateLinkedFileAtURL:(NSURL *)url` |
| 5237 | `- (void)openOrCreateFileForUrl:(NSURL *)url` |
| 5344 | `+ (NSInvocation *)printCompletionForDelegate:(id)delegate selector:(SEL)selector context:(void *)context` |
| 5361 | `- (void)document:(NSDocument *)doc didPrint:(BOOL)ok context:(void *)context` |
| 5416 | `- (NSDictionary *)previewDraft` |
| 5425 | `- (BOOL)flushPreviewEditor` |
| 5438 | `- (void)saveDocument:(id)sender` |
| 5443 | `- (void)saveDocumentAs:(id)sender` |
| 5448 | `- (void)canCloseDocumentWithDelegate:(id)delegate shouldCloseSelector:(SEL)selector contextInfo:(void *)contextInfo` |
| 5458 | `- (void)installPreviewEditor` |
| 5655 | `- (NSString *)escapePreviewPlainText:(NSString *)text` |
| 5668 | `- (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement` |
| 5673 | `- (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement preservingSelection:(NSRange)selection` |
| 5678 | `- (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement preservingSelection:(NSRange)selection restoringRange:(NSRange)restoring` |
| 5715 | `- (NSDictionary *)verifiedPreviewSelection:(NSDictionary *)payload` |
| 5761 | `- (BOOL)applyPreviewEditPayload:(NSDictionary *)payload` |
| 6077 | `- (BOOL)queuePendingPreviewFormattingPayload:(NSDictionary *)payload` |
| 6116 | `- (BOOL)performPreviewFormattingAction:(NSString *)action value:(NSString *)value` |
| 6132 | `- (void)handlePreviewEdit:(NSURL *)url` |
| 6155 | `- (NSDictionary<NSString *, NSString *> *)queryItemsByNameForURL:(NSURL *)url` |
| 6172 | `- (void)handleCheckboxToggle:(NSURL *)url` |
| 6222 | `+ (NSString *)toggleCheckboxAtIndex:(NSUInteger)index inMarkdown:(NSString *)markdown` |
| 6239 | `- (void)startFileWatching` |
| 6284 | `- (void)stopFileWatching` |
| 6296 | `- (void)handleExternalFileChange` |
| 6335 | `- (void)processExternalFileChange` |
| 6379 | `- (BOOL)shouldPromptBeforeReloadingExternalChanges` |
| 6384 | `- (void)promptForReloadWithExternalChanges` |
| 6414 | `- (void)presentExternalChangeAlertWithCompletion:(void (^)(BOOL shouldReload))completion` |
| 6443 | `- (void)reloadFromDisk` |
| 6474 | `- (void)applyPreviewZoom` |
| 6489 | `- (void)stepDocumentZoomDirection:(NSInteger)direction` |
| 6537 | `- (IBAction)selectDocumentZoom:(id)sender` |

## Registre des branches et invariants (nouvelle lecture)

| Parcours / symboles | Branches relues et conclusions |
| --- | --- |
| Helpers C `MPNormalizePreviewSelectionText`, `MPPreviewSourceSeparators` | CRLF/CR normalisés seulement dans comparaison ; séparateurs reconstruits entre runs ordonnés et bornés. UTF-16 n'est jamais découpé au milieu d'un surrogate. |
| JS PDF `kMPPDFSnapshotJS`, `kMPPreparePDFAnchorsJS` | CSSOM lisible/non lisible, imports/règles groupées, pseudo-sélecteurs, exceptions et restore inverse ; identité UUID, attributs/href restaurés, pas de publication quand snapshot diverge. |
| Helpers préférences/zoom/couleur/URL + catégories | Defaults keys bornés, dispatch_once, nil/body absent, flags Hoedown réglés selon préférences, normalisation URL fragment/query, zoom partagé et borné. |
| `MPPreviewResourceHTML` / panneau Find | Sans head => reload ; scripts du body inclus dans signature. Command/Shift-G/F/E et Escape, recherche native source ou rendu selon focus, pas d'écriture source pour Find. |
| Init/nib/sidebar | Dependencies absentes => no-op ; setup async fermé => abandon ; observe/unobserve ; root canonique, workspace distinct ignoré, réouverture collapsed pane, user drag seul broadcast, open existing/new/cancel/error. |
| reload/close/save/data | Selection clamp, loadedString consommée seulement si dépendances prêtes, génération scroll retardé, close idempotent et observers/timers/queue annulés. Safe-save local vs réseau ; dataOfType flush synchronisé main ; refus draft protège texte. Ordre writeToURL/newline corrigé avant isSelfSaving/génération et source ; helper commun avec dataOfType, refus sans mutations couvert par vrai draft WebView et fichier. |
| Rendu | Draft dirty => deferred ; avant first-ready reload autorisé ; rendering en cours => pending ; printing => abandon ; ressources/head/theme/base actual vs cached => reload ou body. Références privées UI ; global nommé autorise fonction réelle seulement ; callbacks MathJax générations ; erreurs main-frame libèrent état/handlers. |
| Éditeur / UI | IME marked text, autocompletion/matching-pair, tab/return/backspace/home et surrogate glyph, indentation/paragraph/table ; valeurs menu état/focus ; collapse garde un pane visible. Les conversions source passent par le nouvel oracle renderer de la dépendance Autocomplete corrigée et ses preuves ciblées. |
| Notifications / progression / KVO | Ownership Editor/Preview/Neither, live-scroll/coalescence/layout/sync-toggle ; progression distance nulle=100%, clamp/non-finite ; frame observer et event monitor retirés ; count selection vs total et throttle. |
| Export / impression | Fresh render obligatoire ; file publication atomique ; export PDF single-slot, snapshots original/context/génération/CSSOM, metadata print réussie, finally restore/delete tmp, erreur propagée et delegate retenu. |
| Classement et alignement sync | Fences/ATX/Setext/images/HR/list/paragraph pending ; approximation regex/DOM attendue et LCS classes alignées. Matrix bornée ~8 MiB, fallback monotone, type absent min-count. Divisions et documents courts clampés ; cursor extra-line fragment. |
| Navigation / fichiers | URL actuelle ignored ; scope canonique et executable/app blocked ; création seulement dans scope du document enregistré ; missing/cancel/error présentés ; MIME/MathJax ressource locale. |
| Mapping preview `installPreviewEditor` | Source renderer==éditeur, token metadata exact, édition fermée/impression refusée ; spans privés connectés ; node cap2000, occurrences cap64 et budget128 ; anchor/probe ordered-DOM et whitespace borné, ambiguïté => exclusion ; continuation annulée si source a changé. |
| Transaction preview | Types/token/source/IDs/nombres finite/plages/runs/order/surrogates/text/gaps ; replace100k sans newline/control et Markdown escape ; source-endpoints dans remplacement, invalid range => refus ; selected source proof seule authority. |
| Conversions / styles | Lignes non sélectionnées intactes ; Setext prouvé p→h ; hiérarchie originale quote/list/h ; fermeture ATX et texte littéral ; sortie tag+texte visible vérifiée, une tentative escape puis refus. Wrappers callout/toggle et interdiction :::, fences longues, math $$ guards. Styles en ligne helper unique/rollback prefs ; math inline seul run et enabled. |
| Queue / bridge | Native et popup helper commun, token/types/états/action/value ; ancienne sélection différente => annulation ; replay payload frais ; replace/refresh non enqueued ; mauvais bridge garde draft ou montre refus ; URL JSON200k. |
| Checkboxes / watchers | token+source renderer+offset/[state] proof, decimal ID overflow guard ; modification undoable. Vnode generations/local volume/stale SaveAs/closed, bursts coalescés, prompt protège dirty/draft ; Keep et absence fenêtre conservent source, Discard lit données actuelles. |

La première lecture complète de cette nouvelle passe (6546/2673 lignes) a révélé le défaut d’ordre draft/newline. Après rouge réel puis correction, les deux fichiers ont été intégralement relus une seconde fois dans les plages finales ci-dessus. Aucun autre défaut confirmé ni code caché/obfusqué identifié dans ces fichiers. Ce constat ne remplace pas les contrôles globaux restant au parent.

## Preuve du dernier défaut et origine

`testPreviewDraftIsCommittedBeforeSaveAddsTrailingNewline` : rouge réel dans `source-headings-final-green-autosave-red.log` (5 assertions : save refusé, ancienne source normalisée et pas de fichier). Cause présente dans le code fusionné : draft flushé par dataOfType seulement après newline ajouté par writeToURL. Correctif : flush commun avant toute mutation ; draft périmé refusé sans newline, generation/isSelfSaving/fichier inchangés ; draft conservé ; source restaurée puis save écrit `Changed text\n`. Vert réel dans `pass2-final-targets-green.log`, 7 tests sans échec, 2.217 s, preferences restaurées.

Les anciens tests historiques de filesystem/dirty flags et la tautologie preservesVersions sont lus/analy­sés mais ne servent pas de preuves de sauvegarde réelle. Aucun changement de leur contrat ni suppression sans preuve d’usage.

## Registre complet Lifecycle (dernière lecture)

Toutes les implémentations ci-dessous, infrastructures incluses, ont été lues avec leurs branches, fixtures, assertions et restaurations. Les signatures indexées ne constituent pas une preuve automatique de validité.

| Ligne | Signature |
| --- | --- |
| 43 | `- (instancetype)init` |
| 93 | `- (void)dealloc` |
| 158 | `- (void)parseAndRenderNow` |
| 172 | `- (void)parseAndHighlightNow` |
| 176 | `- (void)clearHighlighting` |
| 179 | `- (void)readClearTextStylesFromTextView` |
| 193 | `- (void)document:(NSDocument *)document printed:(BOOL)success context:(void *)context` |
| 206 | `- (instancetype)init` |
| 211 | `- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html` |
| 216 | `- (BOOL)presentError:(NSError *)error` |
| 234 | `- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSInteger))completion` |
| 256 | `- (void)setUp` |
| 276 | `- (void)tearDown` |
| 293 | `- (void)testDocumentDirtyFlagAfterEdit` |
| 311 | `- (void)testDocumentDirtyFlagAfterMultipleEdits` |
| 325 | `- (void)testDocumentDirtyFlagAfterUndoRedo` |
| 345 | `- (void)testUntitledDocumentDirtyFlag` |
| 365 | `- (void)testDocumentRevertClearsChanges` |
| 393 | `- (void)testDocumentRevertFromDisk` |
| 420 | `- (void)testDocumentEncodingDetectionUTF8` |
| 439 | `- (void)testDocumentEncodingDetectionUTF8BOM` |
| 456 | `- (void)testDocumentEncodingDetectionASCII` |
| 476 | `- (void)testDocumentWithNoExtension` |
| 495 | `- (void)testDocumentWithUnusualExtension` |
| 517 | `- (void)testSaveWithFileModifiedExternally` |
| 549 | `- (void)testDocumentDetectsExternalChange` |
| 579 | `- (void)testOpenFileDeletedDuringEdit` |
| 607 | `- (void)testDocumentFileURLAfterFileDeleted` |
| 631 | `- (void)testReadableTypes` |
| 640 | `- (void)testWritableTypesForSaveOperation` |
| 651 | `- (void)testAutosavesInPlaceRespectsPreference` |
| 670 | `- (void)testPreservesVersions` |
| 681 | `- (void)testDataOfTypeWithEmptyDocument` |
| 694 | `- (void)testReadFromDataSetsLoadedString` |
| 714 | `- (void)testVeryLongFileName` |
| 744 | `- (void)testSpecialCharactersInFileName` |
| 758 | `- (void)testUnicodeFileName` |
| 787 | `- (void)wireDocument:(MPDocument *)doc intoRenderer:(MPSpyRenderer **)rendererOut highlighter:(MPSpyHighlighter **)highlighterOut editor:(MPEditorView *__strong *)editorOut` |
| 808 | `- (void)testNewDocumentTriggersRenderOnReload` |
| 828 | `- (void)testNewDocumentTriggersHighlightOnReload` |
| 846 | `- (void)testExistingDocumentClearsHighlightingBeforeReloadHighlight` |
| 870 | `- (void)testExistingDocumentTriggersRenderOnReload` |
| 888 | `- (void)testReloadConsumesLoadedString` |
| 905 | `- (void)testReloadSetsEditorStringFromLoadedString` |
| 925 | `- (void)testReloadIsNoOpWhenDependenciesNotReady` |
| 946 | `- (void)testReloadDoesNotModifyEditorStringForNewDocument` |
| 972 | `- (void)testPreReadyRendersNotBlockedByAlreadyRenderingInWeb` |
| 998 | `- (void)testPostReadyRendersBlockedByAlreadyRenderingInWeb` |
| 1024 | `- (void)testRendersNotBlockedWhenAlreadyRenderingInWebIsNO` |
| 1086 | `- (void)testRendererBaseURLForOpenedFileAvoidsRealDocumentFile` |
| 1109 | `- (void)testWorkspaceRootURLDefaultsToNilAndIsSettable` |
| 1118 | `- (void)testPrintCompletionRetainsDelegateAndDeliversArguments` |
| 1137 | `- (void)testEditorFootnoteParsingFollowsPreferenceAndPreservesMath` |
| 1175 | `- (void)testUnderlineActionKeepsUnderlineMeaningWithExtensionEnabledOrDisabled` |
| 1200 | `- (void)testBackspaceDeletesSelectionWithoutDeletingMatchingPairAroundIt` |
| 1219 | `- (void)testSmartHomeWithSurrogatePairMovesToFirstContentCharacter` |
| 1237 | `- (void)testPDFExportAllowsOnePendingPanelAndCanRetryAfterCancellation` |
| 1259 | `- (void)testAnEarlierSaveTimerCannotReloadWhileTheLatestSaveIsProtected` |
| 1289 | `- (void)testChangedHeadScriptsReloadAndUnchangedHeadPreservesJavaScriptState` |
| 1329 | `- (void)testPreviewFindActionsSearchRenderedTextWithoutChangingMarkdown` |
| 1395 | `- (void)testPreviewFormattingErrorBelongsToSelectionAndDeselectHidesPanel` |
| 1436 | `- (void)testPreviewFormattingInsideWordsUsesMarkdownAndRendersStyles` |
| 1500 | `- (void)assertPreviewBlockSource:(NSString *)source texts:(NSArray<NSString *> *)texts value:(NSString *)value expected:(NSString *)expected HTML:(NSString *)expectedHTML` |
| 1507 | `- (void)assertPreviewBlockSource:(NSString *)source texts:(NSArray<NSString *> *)texts value:(NSString *)value expected:(NSString *)expected HTML:(NSString *)expectedHTML tasks:(BOOL)tasks` |
| 1559 | `- (void)testPreviewBlockConversionPreservesBlankSeparators` |
| 1568 | `- (void)testPreviewBlockConversionLeavesUnselectedSourceBetweenParagraphsUnchanged` |
| 1575 | `- (void)testPreviewBlockConversionConsumesSetextUnderlineWithoutTouchingNeighborRule` |
| 1587 | `- (void)testPreviewSetextConversionPreservesCRLFAndStandaloneRules` |
| 1596 | `- (void)testPreviewMixedStylesApplyToAllSelectedCharactersAndPreserveOutsideStyles` |
| 1654 | `- (void)testPreviewEditingChangesOnlyMappedSourceAndRejectsStaleOrInvalidRequests` |
| 1959 | `- (void)testReadingProgressUsesVisiblePaneGeometryAndClampsBoundaries` |
| 2038 | `- (void)testCodeWrappingChangesLayoutWithoutChangingCodeAndExports` |
| 2096 | `- (void)testFirstRealCodeRenderAfterEmptyPreviewLoadsPrismGrammarAndTokens` |
| 2154 | `- (void)testResourceWatcherBurstPublishesOnceAndAnOldWatcherSetCannotPublish` |
| 2201 | `- (void)testHTMLExportReportsWriteFailureAfterRealRenderAndPreservesExistingFile` |
| 2248 | `- (void)testDeferredConsumerSeesCompletedRealMermaidDiagrams` |
| 2303 | `- (void)testDeferredConsumerRestoresLocalHeadAndBaseAfterHTTPNavigation` |
| 2364 | `- (void)testPreviewSetextProofDoesNotConsumeUnderlineAfterATX` |
| 2370 | `- (void)testPreviewControlsPreserveAuthoredIDsAndRunAttributes` |
| 2456 | `- (void)testPreviewParagraphConversionRemovesATXClosingHashes` |
| 2464 | `- (void)testPreviewBlockConversionRespectsActualMarkdownMarkersAndOptions` |
| 2484 | `- (void)testPreviewWrapperConversionRestoresSelectionAcrossRemovedSetextMetadata` |
| 2534 | `- (void)testPreviewPopupQueuesRapidFormattingWithoutReselecting` |
| 2636 | `- (void)testPreviewDraftIsCommittedBeforeSaveAddsTrailingNewline` |


## Validation de livraison après les lectures

Les attentes de contrôles mentionnées plus haut décrivent l'état au moment des lectures. Clôture du parent : **1 471 XCTest, 13 XCUITest, 65 contrats CLI réussis**, syntaxe JS correcte et Release universel signé localement vérifié. Aucun changement de source depuis la version finale intégralement relue. Validation dans le périmètre vérifié, commandes/empreintes/limites dans [la clôture](squashed-cloture.md) et [verification.json](squashed-verification.json).
