# Audit du document et des transactions du visualiseur — commit fusionné

État : analyse terminée sur la version initiale ; corrections et contrôles en cours. Ce document ne certifie pas les contrôles natifs que le parent exécute séparément.

## Lecture réelle

- `MacDown/Code/Document/MPDocument.m` : version dbc6b23, 6 320 lignes, lues intégralement par plages contiguës 1–800, 801–1600, 1601–2400, 2401–3200, 3201–4000, 4001–4800, 4801–5250, 5251–5600, 5601–5980 et 5981–6320. La sortie 4801–5600 initialement tronquée a été relue en plages plus petites ; 5190–5400 a été repris explicitement pour supprimer toute lacune.
- `MacDownTests/MPDocumentLifecycleTests.m` : version initiale 2 214 lignes lue intégralement (1–700, 701–1300, 1301–1750, 1751–2214 ; 1510–1635 repris sans troncature).
- Dépendances lues intégralement : `MPDocument.h`, `MPRenderer.h`, `NSTextView+Autocomplete.m` (729 lignes), `DOMNode+Text.m` (152 lignes), `preview-edit.js` (278 lignes, avant corrections par l’agent JS), `docs/features/edition-apercu.md`.
- Dépendances examinées aux points de contrat : parseSnapshot/publication/rendu différé de MPRenderer ; reconnaisseurs Setext et préfixes Hoedown dans `Pods/hoedown/src/document.c`. Leur revue intégrale appartient à l’agent renderer.

Empreinte initiale MPDocument.m : `be48148bec57df7324e39dcb2e2ddd372bb8057cc524283116f4034d66af134f`.

## Parcours et invariants examinés

| Parcours | Garanties et branches examinées |
| --- | --- |
| Chargement et configuration | loadedString avant nib, création editor/renderer/highlighter, callbacks après fermeture, initialisation fenêtres, préférences KVO et désinscription unique, sidebar racines canoniques, réactions aux erreurs et fenêtres existantes. |
| Sauvegarde / brouillon visuel | draft uniquement main-thread et document actif ; flush avant save/saveAs/dataOfType/canClose/exports ; refus garde la saisie récupérable et bloque la sauvegarde ; UTF-8, contrôles et nouvelles lignes refusés ; source inchangée en cas de refus. |
| Navigation / bridge | x-macdown-preview intercepté uniquement WebView/mainFrame propriétaire ; token source et renderer courants, source identique au snapshot ; id entier/borné, UTF-16 sans coupe surrogate ; actions et paramètres autorisés ; checkbox token, offsets littéraux et génération ; garde fichiers exécutables et scope création. |
| Rendu différé / publication | brouillon retarde publication ; initial render ne reste pas bloqué ; coalescence pendant rendu, ressource head/script et URL base vérifiées ; générations MathJax, clôture et callbacks obsolètes ; DOM body replacement réinstalle commandes ; résultat consommé par exports/print après fin. |
| Mise en forme inline | adapter menu natif et panneau consomment la même sélection vérifiée ; ordre des runs, texte visible, tous les runs touchés requis ; source transmise au helper unique ; préférences intra/underline rétablies après refus ; résultat candidat comparé au texte réellement sélectionné. |
| Mise en forme bloc | sélection étendue aux lignes mais seuls caractères de texte sélectionnés peuvent décider quelles lignes convertir ; conserver blancs, images, commentaires et voisins ; supprimer marqueurs réels de titre ; restaurer les bornes malgré marqueurs insérés à l’intérieur de la sélection. |
| Sélection / commandes rapprochées | conserver source-range et occurrence, jamais DOM obsolète ; file native rejouée uniquement si même source/ancienne sélection/focus ; changement ou collapse annule ; restauration produit nouveaux runs dans nouveau DOM. |
| Géométrie / contrôles auxiliaires | scroll-owner, sync aller/retour/cursor, divisions et vues courtes, types LCS bornés mémoire, scrolling/resize progress throttlé, wordcount, menus et zoom ; réglages rendent voisins accessibles sans écrire au mauvais curseur. |
| Watchers / impression | générations SaveAs/close/reload, coalescence et prompts protégeant modifications ; instantanés PDF et publication atomique, restauration CSSOM et fichiers temporaires ; files d’exports annulées sur fermeture/échec. |

## Défauts et hypothèses

| ID | Constat et preuve | État |
| --- | --- | --- |
| DOC-BLOCK-01 | Préfixe appliqué à toutes lignes de la plage continue : `first\n\nsecond` devient `# first\n# \n# second`; même cause transforme commentaire/image sans texte sélectionné. Régression native réelle avant correction dans native-red.log et native-block-extra-red.log. | En correction ; seules lignes intersectant runs proven transformées. |
| DOC-SETEXT-01 | Sélection de Title dans `Title\n====` ne comprend pas l’underline ; conversion texte normal la laisse en place donc heading inchangé ; H3 laisse marqueurs visibles. Rouge natif confirmé. | En correction. |
| DOC-ATX-01 | Conversion `# Title ###` en paragraphe laisse `Title ###` au rendu, alors que hashes finaux sont syntaxe de titre. Rouge natif supplémentaire confirmé. | En correction. |
| DOC-RESTORE-01 | Conversion multi-paragraphes insère préfixes au milieu de la plage ; ancienne chaîne source totale n’existe plus dans remplacement, target NSNotFound supprime restauration. Régression WebView ajoutée. | À vérifier par parent avant correction. |
| DOC-COUNT-01 | DOMDocument.textCount compte les libellés du panneau même display:none ; compteur ne distingue pas UI nouvellement injectée du document. Chaîne lue intégralement. | Transmis au parent propriétaire DOMNode+Text.m. |
| JS-ERROR-01 | Refus reste sur nouvelle sélection admissible, message obsolète : sélection A/refus/scroll puis B. | Rouge natif confirmé ; agent JS corrige. |
| JS-ID-01 | IDs HTML auteur en collision avec panneau/style sont réutilisés et peuvent être écrasés par JS ou déplacés par body replacement. | Agent JS corrige refs propriétaires ; adaptation native coordonnée. |
| LIM-LITERAL | Texte remplacé avec caractères Markdown échappés peut nécessiter éditeur gauche ensuite car mapping exige fragments littéraux exacts ; même classe documentée que entités/transforms. Pas de fausse association source autorisée pour contourner la limite. | Limite explicite, pas défaut de données confirmé. |
| SOURCE-HEADINGS | Ancienne commande de l’éditeur source ne gère pas Setext ou closing ATX correctement non plus. Elle précède le squash et permet édition raw Markdown non rendu ; pas la même admissibilité de sélection que preview. | Défaut de consommateur confirmé pendant la nouvelle passe ; corrigé par l’agent renderer dans Autocomplete avec oracle renderer, sept callers MPDocument migrés. Tests source Setext/closing ATX/contexte réel verts. La limite initialement supposée ne justifie plus un classement hors correction. |

## Seconde passe (en cours)

Axes distincts : caractères UTF-16, IDs HTML auteur, texte produit reconsommable, continuation commandes sur changement de passage, syntaxe Setext/ATX réellement reconnue par Hoedown (ne pas retirer HR/littéraux), invisibles entre runs, compteur document contaminé par UI. Chaque nouveau finding reste ouvert jusqu’à preuve finale actuelle.

## Fonctions C, blocs et JavaScript embarqué

Lues intégralement avec le fichier : `MPNormalizePreviewSelectionText`, `MPPreviewSourceSeparators`, `MPEditorPreferenceKeyWithValueKey`, `MPEditorKeysToObserve`, `MPEditorPreferencesToObserve`, `MPDocumentZoomLevels`, `MPRectStringForAutosaveName`, `MPAreNilableStringsEqual`, `MPGetWebViewBackgroundColor`, `MPPreviewResourceHTML`, `MPGetPreviewLoadingCompletionHandler`, `MPScanFenceMarker`. Les constantes JavaScript `kMPPDFSnapshotJS` / `kMPPreparePDFAnchorsJS` et les scripts locaux DOM replacement, scan, probes et édition ont été examinés avec leurs consommateurs natifs.

Branches distinctes reprises : normalization CR/CRLF/LF et limites du caller ; lecture bornée des séparateurs ; dispatch_once des registres ; nil/identité pour chaînes ; absence body/couleur CSS ; absence head et scripts multilignes ; weak→strong, génération obsolète/fermeture, scroll-owner et flush-window ; indentation 0–3 / 4+, marker différent, run <3, info contenant backtick et pointeurs de sortie NULL ; PDF CSSOM cross-origin indisponible et restauration après échec ; bornes sources UTF-16, identité DOM propriétaire et rejeu post-render.

## Registre exhaustif des méthodes / fonctions

Les méthodes ci-dessous ont été examinées dans la lecture complète : chemins nominal/nil, refus, erreur, états de rendu et callbacks associés. Ce relevé constitue la carte des symboles, pas une validation automatique.

- L311 : `- (NSString *)absoluteBaseURLString`
- L325 : `- (NSScrollView *)enclosingScrollView`
- L334 : `- (int)extensionFlags`
- L364 : `- (int)rendererFlags`
- L409 : `- (void)sendEvent:(NSEvent *)event`
- L417 : `- (BOOL)performKeyEquivalent:(NSEvent *)event`
- L440 : `- (void)cancelOperation:(id)sender { [self orderOut:sender]; }`
- L632 : `+ (NSArray<NSNumber *> *)editorReferenceKindsForMarkdown:(NSString *)markdown`
- L637 : `+ (CGFloat)previewYForCursorY:(CGFloat)cursorDocumentY`
- L645 : `+ (void)alignEditorYs:(NSArray<NSNumber *> *)editorYs`
- L797 : `- (MPPreferences *)preferences`
- L802 : `- (NSString *)markdown`
- L807 : `- (void)setMarkdown:(NSString *)markdown`
- L838 : `- (NSString *)html`
- L843 : `- (BOOL)toolbarVisible`
- L848 : `- (BOOL)previewVisible`
- L853 : `- (BOOL)editorVisible`
- L858 : `- (BOOL)needsHtml`
- L867 : `- (NSString *)wordCountTitleForKey:(NSString *)key number:(NSUInteger)value`
- L875 : `- (void)applyWordsTitle:(NSUInteger)value selected:(BOOL)selected`
- L882 : `- (void)applyCharactersTitle:(NSUInteger)value selected:(BOOL)selected`
- L890 : `- (void)applyCharactersNoSpacesTitle:(NSUInteger)value selected:(BOOL)selected`
- L901 : `- (void)setTotalWords:(NSUInteger)value`
- L908 : `- (void)setTotalCharacters:(NSUInteger)value`
- L915 : `- (void)setTotalCharactersNoSpaces:(NSUInteger)value`
- L922 : `- (void)setAutosaveName:(NSString *)autosaveName`
- L930 : `- (NSUInteger)mathJaxRenderGeneration`
- L937 : `- (instancetype)init`
- L964 : `- (NSString *)windowNibName`
- L969 : `- (void)windowControllerDidLoadNib:(NSWindowController *)controller`
- L1110 : `- (void)registerSharedPreferenceObservers`
- L1121 : `- (void)unregisterSharedPreferenceObservers`
- L1130 : `+ (NSRange)selectionRange:(NSRange)range clampedToLength:(NSUInteger)length`
- L1148 : `- (void)setWorkspaceRootURL:(NSURL *)workspaceRootURL`
- L1154 : `- (void)installFolderSidebarForController:(NSWindowController *)controller`
- L1220 : `- (void)outerSplitDidResize:(NSNotification *)note`
- L1236 : `- (BOOL)isSidebarVisible`
- L1244 : `- (void)showSidebarPane`
- L1273 : `- (void)hideSidebarPane`
- L1283 : `- (IBAction)toggleFolderSidebar:(id)sender`
- L1300 : `- (void)sidebarSyncDidChange:(NSNotification *)note`
- L1325 : `+ (MPDocument *)openDocumentForFileURL:(NSURL *)url`
- L1335 : `+ (NSError *)sidebarOpenErrorForError:(NSError *)error URL:(NSURL *)url`
- L1358 : `- (void)presentSidebarOpenError:(NSError *)error forURL:(NSURL *)url`
- L1365 : `- (void)folderSidebar:(MPFolderSidebarViewController *)sidebar`
- L1419 : `- (void)reloadFromLoadedString`
- L1490 : `- (void)close`
- L1569 : `+ (BOOL)autosavesInPlace`
- L1574 : `+ (NSArray *)writableTypes`
- L1579 : `- (BOOL)isDocumentEdited`
- L1590 : `- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName`
- L1653 : `- (BOOL)writeSafelyToURL:(NSURL *)url ofType:(NSString *)typeName`
- L1694 : `- (BOOL)shouldBypassSafeSaveForURL:(NSURL *)url`
- L1699 : `- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError`
- L1713 : `- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName`
- L1733 : `- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel`
- L1782 : `- (NSPrintInfo *)printInfo`
- L1793 : `- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)printSettings`
- L1812 : `- (void)printDocumentWithSettings:(NSDictionary *)printSettings`
- L1836 : `- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item`
- L1930 : `- (void)splitViewDidResizeSubviews:(NSNotification *)notification`
- L1961 : `- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview`
- L1969 : `- (NSUndoManager *)undoManagerForTextView:(NSTextView *)textView`
- L1974 : `- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector`
- L1989 : `- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)range`
- L2020 : `- (BOOL)textViewShouldInsertTab:(NSTextView *)textView`
- L2035 : `- (BOOL)textViewShouldInsertBacktab:(NSTextView *)textView`
- L2041 : `- (BOOL)textViewShouldInsertNewline:(NSTextView *)textView`
- L2057 : `- (BOOL)textViewShouldDeleteBackward:(NSTextView *)textView`
- L2075 : `- (BOOL)textViewShouldMoveToLeftEndOfLine:(NSTextView *)textView`
- L2107 : `- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)dataSource`
- L2124 : `- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame`
- L2147 : `- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame`
- L2155 : `- (void)finishPreviewRender`
- L2173 : `- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error`
- L2194 : `- (void)webView:(WebView *)webView`
- L2271 : `- (BOOL)webView:(WebView *)webView doCommandBySelector:(SEL)selector`
- L2290 : `- (BOOL)previewHasFindFocus`
- L2299 : `- (BOOL)validateDocumentFindAction:(NSMenuItem *)item`
- L2320 : `- (IBAction)performDocumentFindAction:(id)sender`
- L2328 : `- (void)performPreviewFindAction:(NSTextFinderAction)action`
- L2401 : `- (void)findPreviewText:(NSSearchField *)field`
- L2409 : `- (void)findPreviewAdjacent:(NSSegmentedControl *)sender`
- L2415 : `- (NSUInteger)webView:(WebView *)webView`
- L2421 : `- (NSArray *)webView:(WebView *)sender`
- L2445 : `- (void)reloadPreview:(id)sender`
- L2454 : `- (BOOL)rendererLoading {`
- L2458 : `- (NSString *)rendererMarkdown:(MPRenderer *)renderer`
- L2463 : `- (NSString *)rendererHTMLTitle:(MPRenderer *)renderer`
- L2472 : `- (int)rendererExtensions:(MPRenderer *)renderer`
- L2477 : `- (BOOL)rendererHasSmartyPants:(MPRenderer *)renderer`
- L2482 : `- (BOOL)rendererRendersTOC:(MPRenderer *)renderer`
- L2487 : `- (NSString *)rendererStyleName:(MPRenderer *)renderer`
- L2492 : `- (BOOL)rendererDetectsFrontMatter:(MPRenderer *)renderer`
- L2497 : `- (BOOL)rendererWrapsCodeBlocks:(MPRenderer *)renderer`
- L2502 : `- (BOOL)rendererHasSyntaxHighlighting:(MPRenderer *)renderer`
- L2507 : `- (BOOL)rendererHasMermaid:(MPRenderer *)renderer`
- L2512 : `- (BOOL)rendererHasGraphviz:(MPRenderer *)renderer`
- L2517 : `- (MPCodeBlockAccessoryType)rendererCodeBlockAccesory:(MPRenderer *)renderer`
- L2522 : `- (BOOL)rendererHasMathJax:(MPRenderer *)renderer`
- L2527 : `- (NSString *)rendererHighlightingThemeName:(MPRenderer *)renderer`
- L2532 : `- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html`
- L2735 : `- (NSURL *)rendererBaseURL:(MPRenderer *)renderer`
- L2767 : `- (NSURL *)previewSafeBaseURL:(NSURL *)baseURL`
- L2786 : `- (void)resourceWatcherSet:(MPResourceWatcherSet *)set`
- L2811 : `- (void)makeWindowControllers`
- L2818 : `- (void)editorTextDidChange:(NSNotification *)notification`
- L2835 : `- (void)editorSelectionDidChange:(NSNotification *)notification`
- L2881 : `- (void)refreshDocumentWordCountTitles`
- L2890 : `- (void)userDefaultsDidChange:(NSNotification *)notification`
- L2929 : `- (void)handleSyncScrollingEnabled`
- L2951 : `- (void)handleSyncScrollingDisabled`
- L2963 : `- (void)editorFrameDidChange:(NSNotification *)notification`
- L2976 : `- (void)willStartLiveScroll:(NSNotification *)notification`
- L2983 : `-(void)didEndLiveScroll:(NSNotification *)notification`
- L2991 : `- (void)willStartPreviewLiveScroll:(NSNotification *)notification`
- L3001 : `- (void)didEndPreviewLiveScroll:(NSNotification *)notification`
- L3019 : `- (void)refreshHeaderCacheAfterResize`
- L3029 : `- (void)windowDidEndLiveResize:(NSNotification *)notification`
- L3037 : `- (void)windowDidChangeFullScreen:(NSNotification *)notification`
- L3045 : `- (void)editorBoundsDidChange:(NSNotification *)notification`
- L3060 : `- (void)didRequestEditorReload:(NSNotification *)notification`
- L3067 : `- (void)didRequestPreviewReload:(NSNotification *)notification`
- L3074 : `- (void)previewBoundsDidChange:(NSNotification *)notification`
- L3092 : `- (void)scheduleReadingProgressUpdate`
- L3101 : `- (void)observeReadingProgressDocumentView`
- L3117 : `- (void)readingProgressDocumentDidChange:(NSNotification *)notification`
- L3122 : `- (void)setupReadingProgress`
- L3174 : `- (void)updateReadingProgress`
- L3198 : `- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object`
- L3227 : `- (IBAction)copyHtml:(id)sender`
- L3245 : `- (IBAction)exportHtml:(id)sender`
- L3280 : `- (IBAction)exportPdf:(id)sender`
- L3327 : `- (BOOL)preparePDFAnchorSession`
- L3354 : `- (void)restorePDFAnchorSession`
- L3372 : `- (BOOL)PDFExportSnapshotIsCurrent`
- L3381 : `- (void)publishPDFDocument:(PDFDocument *)document atURL:(NSURL *)url`
- L3389 : `- (void)postProcessExportedPDFAtURL:(NSURL *)url`
- L3436 : `- (IBAction)convertToH1:(id)sender`
- L3442 : `- (IBAction)convertToH2:(id)sender`
- L3448 : `- (IBAction)convertToH3:(id)sender`
- L3454 : `- (IBAction)convertToH4:(id)sender`
- L3460 : `- (IBAction)convertToH5:(id)sender`
- L3466 : `- (IBAction)convertToH6:(id)sender`
- L3472 : `- (IBAction)convertToParagraph:(id)sender`
- L3478 : `- (IBAction)toggleStrong:(id)sender`
- L3484 : `- (IBAction)toggleEmphasis:(id)sender`
- L3490 : `- (IBAction)toggleInlineCode:(id)sender`
- L3496 : `- (IBAction)toggleStrikethrough:(id)sender`
- L3502 : `- (IBAction)toggleUnderline:(id)sender`
- L3511 : `- (IBAction)toggleHighlight:(id)sender`
- L3516 : `- (IBAction)toggleComment:(id)sender`
- L3521 : `- (IBAction)toggleLink:(id)sender`
- L3541 : `- (IBAction)toggleImage:(id)sender`
- L3582 : `+ (NSString *)tableInsertionForContent:(NSString *)content`
- L3650 : `- (IBAction)insertTable:(id)sender`
- L3679 : `- (IBAction)toggleOrderedList:(id)sender`
- L3684 : `- (IBAction)toggleUnorderedList:(id)sender`
- L3690 : `- (IBAction)toggleBlockquote:(id)sender`
- L3695 : `- (IBAction)indent:(id)sender`
- L3703 : `- (IBAction)unindent:(id)sender`
- L3708 : `- (IBAction)insertNewParagraph:(id)sender`
- L3731 : `- (IBAction)setEditorOneQuarter:(id)sender`
- L3736 : `- (IBAction)setEditorThreeQuarters:(id)sender`
- L3741 : `- (IBAction)setEqualSplit:(id)sender`
- L3746 : `- (IBAction)toggleToolbar:(id)sender`
- L3751 : `- (IBAction)togglePreviewPane:(id)sender`
- L3756 : `- (IBAction)toggleEditorPane:(id)sender`
- L3761 : `- (IBAction)toggleAutoSave:(id)sender`
- L3767 : `- (IBAction)toggleInvisibleCharacters:(id)sender`
- L3773 : `- (IBAction)render:(id)sender`
- L3788 : `- (void)invalidateStyleCaches`
- L3828 : `- (void)performAfterRender:(void (^)(void))handler`
- L3852 : `- (void)invokeRenderCompletionHandlers`
- L3866 : `- (void)toggleSplitterCollapsingEditorPane:(BOOL)forEditorPane`
- L3904 : `- (void)applyEditorStartInPreviewModePreference`
- L3925 : `- (void)setupEditor:(NSString *)changedKey`
- L4068 : `- (void)adjustEditorInsets`
- L4084 : `- (void)redrawDivider`
- L4110 : `- (CGFloat)previewScale`
- L4124 : `- (CGFloat)zoomMultiplier`
- L4130 : `- (void)setZoomMultiplier:(CGFloat)zoomMultiplier`
- L4136 : `- (void)scaleWebview`
- L4145 : `- (NSFont *)zoomedEditorFont`
- L4154 : `- (void)applyEditorFontAndParagraphStyle`
- L4185 : `- (IBAction)zoomIn:(id)sender`
- L4190 : `- (IBAction)zoomOut:(id)sender`
- L4195 : `- (IBAction)resetZoom:(id)sender`
- L4200 : `- (void)applyCurrentZoom`
- L4245 : `-(void) updateHeaderLocations`
- L4341 : `+ (NSArray<NSNumber *> *)editorReferenceKindsForMarkdown:(NSString *)markdown`
- L4579 : `+ (void)alignEditorYs:(NSArray<NSNumber *> *)editorYs`
- L4687 : `- (void)validateHeaderLocationAlignment`
- L4723 : `- (void)syncScrollers`
- L4831 : `- (void)syncScrollersToCursor`
- L4900 : `+ (CGFloat)previewYForCursorY:(CGFloat)cursorDocumentY`
- L4986 : `- (void)syncScrollersReverse`
- L5076 : `- (void)setSplitViewDividerLocation:(CGFloat)ratio`
- L5103 : `- (NSString *)presumedFileName`
- L5136 : `- (void)updateWordCount`
- L5156 : `- (void)scheduleWordCountUpdate`
- L5181 : `- (BOOL)isCurrentBaseUrl:(NSURL *)another`
- L5208 : `- (BOOL)canAutomaticallyCreateLinkedFileAtURL:(NSURL *)url`
- L5219 : `- (void)openOrCreateFileForUrl:(NSURL *)url`
- L5326 : `+ (NSInvocation *)printCompletionForDelegate:(id)delegate selector:(SEL)selector context:(void *)context`
- L5343 : `- (void)document:(NSDocument *)doc didPrint:(BOOL)ok context:(void *)context`
- L5398 : `- (NSDictionary *)previewDraft`
- L5407 : `- (BOOL)flushPreviewEditor`
- L5420 : `- (void)saveDocument:(id)sender`
- L5425 : `- (void)saveDocumentAs:(id)sender`
- L5430 : `- (void)canCloseDocumentWithDelegate:(id)delegate shouldCloseSelector:(SEL)selector contextInfo:(void *)contextInfo`
- L5440 : `- (void)installPreviewEditor`
- L5637 : `- (NSString *)escapePreviewPlainText:(NSString *)text`
- L5650 : `- (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement`
- L5655 : `- (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement preservingSelection:(NSRange)selection`
- L5660 : `- (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement preservingSelection:(NSRange)selection restoringRange:(NSRange)restoring`
- L5697 : `- (NSDictionary *)verifiedPreviewSelection:(NSDictionary *)payload`
- L5743 : `- (BOOL)applyPreviewEditPayload:(NSDictionary *)payload`
- L5870 : `- (BOOL)performPreviewFormattingAction:(NSString *)action value:(NSString *)value`
- L5908 : `- (void)handlePreviewEdit:(NSURL *)url`
- L5930 : `- (NSDictionary<NSString *, NSString *> *)queryItemsByNameForURL:(NSURL *)url`
- L5947 : `- (void)handleCheckboxToggle:(NSURL *)url`
- L5997 : `+ (NSString *)toggleCheckboxAtIndex:(NSUInteger)index inMarkdown:(NSString *)markdown`
- L6014 : `- (void)startFileWatching`
- L6059 : `- (void)stopFileWatching`
- L6071 : `- (void)handleExternalFileChange`
- L6110 : `- (void)processExternalFileChange`
- L6154 : `- (BOOL)shouldPromptBeforeReloadingExternalChanges`
- L6159 : `- (void)promptForReloadWithExternalChanges`
- L6189 : `- (void)presentExternalChangeAlertWithCompletion:(void (^)(BOOL shouldReload))completion`
- L6218 : `- (void)reloadFromDisk`
- L6249 : `- (void)applyPreviewZoom`
- L6264 : `- (void)stepDocumentZoomDirection:(NSInteger)direction`
- L6312 : `- (IBAction)selectDocumentZoom:(id)sender`
