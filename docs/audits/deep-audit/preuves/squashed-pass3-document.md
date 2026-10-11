# Nouvelle passe 3 — document et cycle de vie

Cette preuve vient d’une nouvelle lecture à partir de zéro le 9 octobre 2026, après la clôture 17dbbb9. Les conclusions et cases des campagnes précédentes ne sont pas héritées. La lecture historique des fichiers est conservée dans les autres notes.

## Version et lecture effective

- Référence de départ : `17dbbb9ba39746b4c216278b764b2d95fe1ce801`.
- MPDocument.m : 6 556 lignes ; SHA-256 `f2a130c74ff27e646ebe6ec665285e756539aef5442b26b43f99ea66ab7d9fc6`.
- Lifecycle de départ : 2 687 lignes ; SHA-256 `6b4bfa45679e7bac3d6c84915fab75b7720ec8baa6bae2a4cb5f48a26f649c27`.
- Lecture Document complète, sorties non tronquées : 1–600, 601–1200, 1201–1800, 1801–2400, 2401–3000, 3001–3600, 3601–4200, 4201–4800, 4801–5400, 5401–5800, 5801–6200, 6201–6556.
- Lecture Lifecycle complète, sorties non tronquées : 1–500, 501–1000, 1001–1350, 1351–1600, 1601–1850, 1851–2200, 2201–2450, 2451–2687. Les deux nouvelles fonctions ajoutées après cette lecture ont ensuite été lues entièrement.
- Dépendances nécessaires relues : MPDocument.h, MPRenderer.h, MPMathJaxListener.m, MPAutosaving.h, updateHeaderLocations.js ; MPRenderDeferralTests.m entier (471 lignes), contrat docs/features/edition-apercu.md entier. Les dépendances renderer, helper inline, Autocomplete et JS font l’objet des autres preuves fraîches de passe 3, reliées par le suivi principal.

Lecture, analyse, correction et relecture finale intégrale terminées pour les trois fichiers ci-dessous. Les tests ciblés de cette passe sont verts ; les gates complètes sont centralisées par la racine avant livraison.

## Parcours et branches examinés

| Plage Document | Entrées, sorties et branches analysées | Invariants et conclusion fraîche |
| --- | --- | --- |
| 1–440 | Normalisation/séparateurs UTF-16 ; scripts PDF snapshot/préparation/restauration ; zoom presets ; catégories URL/WebView/préférences ; signature ressources ; événements Find | CSSOM inaccessible échoue sans publication ; restauration inverse des règles/attributs propres ; marqueurs UUID, sélecteurs quotés/imbriqués ; signature head+scripts, exclut token renouvelable ; commande Find conserve son panneau. Aucun code obfusqué découvert : chaînes JS inspectées en totalité. |
| 441–797 | Propriétés et enums ; callback de rendu génération/closed ; scanner de fences | États ownership scroll explicites ; callback ancien ignore rendu nouveau ; fences backtick/tilde, longueur, indentation et info invalides distingués. |
| 798–1148 | Accesseurs markdown/html/visibilité/count ; mutation undoable ; init ; nib ; KVO register/unregister ; clamp | Headless et fermeture sûrs ; titre count sélection/total ; undo group ; observers équilibrés ; bornes via soustraction. |
| 1149–1569 | Racine workspace ; sidebar width/show/hide/sync ; ouverture documents/rechargement ; close | Canonicalisation symlink ; conserver un panneau visible ; annulation ouverture sans erreur ; sélection bornée ; close invalide timers/watchers/bridges/queues, nettoyage PDF seulement si non printing. |
| 1570–1846 | Autosave/dirty ; writeToURL/safe network save ; flush draft ; data/read/savepanel ; printInfo/printOperation/printDocument | Flush précède newline et saveGeneration ; UTF-8 invalide refuse ; fallback loadedString ; timers génération ; **PDF/print refus draft perd callback : P3-DOC-PDF**. |
| 1847–2455 | UI validation ; commandes editor/IME ; matching pairs, smart Home ; WebKit resource/load/fail/policy ; find source/preview ; drag | Mainframe uniquement pour bridge ; source/editor focus conservés ; rendered find ne remplace pas HTML ; canClose refuse draft ; navigation exécutable bloquée ; load fail vide PDF slot, mais ne protège pas refus avant rendu. |
| 2456–2828 | Renderer adapters ; publication/draft/pending/printing ; ressources ; fast body vs full load ; safe base ; watcher | Draft modifié diffère publication ; resources signature complète ; DOM owned refs ; typed optional globals ; callback génération ; base sentinel et foreign navigation force full load ; watchers ancienne identité refusés. |
| 2829–3237 | Changements texte/sélection/defaults ; sync ownership ; resize/fullscreen ; reading progress ; KVO | Mutations effectives dirty ; sélection compte seulement si choisie ; progress géométrie réelle 0/100, court=100, nonfinite borné ; monitor installé/retiré selon préférence ; trailing 50ms ; scroll programmatique ne réentre pas. |
| 3238–3446 | Copy HTML/export HTML/PDF ; PDF anchor sessions ; snapshot/current ; atomic publication | HTML échec disque présenté ; PDF unique pending ; tmp et session restaurés en finally ; source/render/DOM fraîcheur vérifiée ; **slot occupé si performAfterRender refuse avant callback**. |
| 3447–3845 | H1–H6/paragraph via oracle source unique ; styles source/preview ; links/images ; tables ; lists/quotes/indent ; panes/settings | Toolbar choisit focus ; preview incompatible jamais fallback cursor ; soulignement Markdown extension ; table bornes/alignment/blank padding ; liens readonly navigation ; nouvelle API renderer snapshot pour toutes sept conversions source. |
| 3846–4262 | Render consumers FIFO ; split collapse ; reader startup ; editor setup/insets/divider/scale/font/zoom | Visibilité ne prouve pas fraîcheur ; queue demande un rendu ; fermeture annule ; print/export doivent terminer même si draft refusé, actuellement manquant ; paragraph style shared ; panneau visible garanti. |
| 4263–4740 | Références DOM/source ; fences/ATX/Setext/images/lists ; LCS et fallback ; align validation | Classifier approximatif uniquement scroll ; aucun mapping source édition fondé sur ce classifier ; allocation matrice limitée 8MiB, fallback linéaire ; coords et types gardés parallèles. |
| 4741–5198 | Sync forward/cursor/reverse ; split reopen ; filenames ; count throttle | Hauteurs visibles nonnulles ; bracket foundMax distinct du zéro ; division guard/taper/clamp ; cursor fragment vs extra fragment ; count trailing 250ms ; titre slash/colon filtré hors frontmatter. |
| 5199–5415 | BaseURL ; open/create link ; retained print completion ; didPrint | Scope dossier résolu ; symlink/exécutable policy ; delegate args retenus et transfer équilibré ; completion PDF nettoie puis transmet succès ; **absence de completion si refus early**. |
| 5416–5760 | Draft/flush/save/canClose ; install mapper ; escaping ; replace/restore ; verified selection | Token/current source/mainframe ; probes occurrence ≤64 par mot et128 par rendu ; nodes≤2000 ; snippets seulement littéraux prouvés ; whitespace bounded ; rollback selection si source différente ; UTF-16 surrogates et tout run recouvert exigés. |
| 5761–6076 | Payload replace/block/inline/math ; Setext ; prefix hierarchy et literal preservation ; endpoints | Payload types/tokens/caps ; aucune insertion HTML ; DOM original détermine la structure à retirer ; code/math quittent domaine éditable ; legacy inline préserve voisins via helper ; **Setext suivant restant redevient heading : P3-DOC-SETEXT**. |
| 6077–6238 | Queue commune popup/native ; URL parsing ; checkbox toggle/live+pure | Pending peut rejouer uniquement formatting/token/type/selection ancienne admissible ; autre sélection annule ; replay revalide source fraîche ; offsets checkbox proven renderer, signed-digit overflow guard ; pas pipeline popup contournant queue. |
| 6239–6556 | File watcher setup/cancel/coalesce ; external prompt/reload ; zoom | Generation/closed/SaveAs guards ; leading throttle explicite 250ms ; prompt unsaved seulement, pas headless modal ; reread at Discard ; UTF-8 failure ne clear dirty ; shared zoom borne50–300%. |

## Analyse intégrale des tests

Les fixtures HTTP réelles, probes print/publication, spy renderer/highlighter et panel contrôlé ont été lues entièrement, avec leurs chemins cleanup. Les tests récents exercent WebView/Hoedown réels jusqu’à la source/rendu consommé : sélection souris, propriétés communes, queue rapide, identité DOM, checkbox click, draft sauvegarde, Mermaid différé, Prism, Find, progress et export failure.

Les tests historiques de fichiers externes 500–730 ne prouvent pas à eux seuls le watcher : certains n’assertent que la lecture du fichier. `testPreservesVersions` contient une assertion tautologique et n’établit pas le contrat de versioning ; aucun verdict fonctionnel de versioning n’est fondé dessus. Les tests de deferral anciens avec returns headless restent limités ; les scénarios WebView récents constituent les preuves jusqu’au consommateur. Aucun résultat de campagne précédente n’est déclaré résultat de cette passe.

## Défauts et seconde passe critique

| ID | Preuve de chaîne et attendu | Protections examinées | État |
| --- | --- | --- | --- |
| P3-DOC-PDF | Draft preview modifié puis source concurrente. PDF panel OK occupe URL/pending ; print appelle performAfterRender qui retourne avant queue sur flushNO ; aucune didPrint, slot bloque les exports suivants. Print delegate doit recevoir NO, slot doit être libéré, source/draft/fichier préservés. | close, load fail, panel cancel, document:didPrint : aucun n’est atteint lors du refus préalable. Recherche exhaustive des mutations pdfExportURL/pending et callers performAfterRender. Test réel nouveau testPDFExportRefusedPreviewDraftReleasesSlotAndCompletesPrint prêt. | Confirmé RED (7 assertions) puis corrigé et GREEN dans cette passe. |
| P3-DOC-SETEXT | Title\n---\n=== : conversion Texte normal consomme --- après preuve locale, puis === restant transforme Title en H1. Le texte normal demandé n’est pas produit. Il faut conserver le voisin littéral et un séparateur protégeant le paragraphe. | Preuves locales singleParagraph/singleHeading portent sur le couple retiré seulement ; bloc prefix prove porte sur ligne Title seule ; pas oracle du contexte final. Même consommateur source traité par renderer agent. Test nouveau testPreviewParagraphSetextConversionPreservesFollowingUnderlineLiteral prêt. | Confirmé RED (2 assertions) puis corrigé et GREEN ; même cause que le consommateur source Autocomplete. |

Seconde passe fraîche : relu les transitions draft→save/export/print/close, les branches de signature reload/fastDOM, la chaîne queue→restore→replay, les références DOM privées, les allocations probes/LCS, et les conversions Setext avec voisins non sélectionnés. Les deux défauts ci-dessus proviennent de ces parcours complets, pas d’un quota.

Hypothèses non retenues : punctuation échappée peut rendre fragment non littéral au prochain rendu ; contrat autorise structures non prouvées readonly, aucune corruption démontrée. Math/code générés perdent volontairement domaine éditable ; toggle collapsed masque corps sans perte source. Jetons bridge garantissent fraîcheur et provenance, pas une frontière d’autorisation contre scripts locaux exécutés dans le même contexte historique. Pas de suppression legacy sans preuve d’usage.

## Version relue après les deux premiers correctifs et vérification fraîche

- MPDocument.m : **6 562 lignes**, SHA-256 `99bf12ed08dae2cef6201d9edf0d1e3fe89b90a2f6b35f65cc48075e39d8e2c1`.
- MPDocumentLifecycleTests.m : **2 753 lignes**, SHA-256 `b36ec5a7967467a6846d84715c8026528e97a861d6de2bc46d9f9424e48154c7`.
- MPRenderDeferralTests.m : **471 lignes**, SHA-256 `4b2bde9d541ac37f404cf6501a97bf8f081c0b5d3dc95d125ec039c92c4033b8`.
- Nouvelle lecture intégrale Document après les deux corrections : 1–800, 801–1600, 1601–2400, 2401–3200, 3201–4000, 4001–4800, 4801–5600, 5601–6100, 6101–6562. La sortie 4801–5600 a été tronquée au milieu ; **5199–5420 a donc été relu explicitement en sortie intégrale**, couvrant entièrement le trou. Aucune fonction ou ligne manquante n’est certifiée sur un résumé.
- Nouvelle lecture intégrale Lifecycle final : 1–700, 701–1400, 1401–1800, 1801–2200, 2201–2500, 2501–2753, sorties intégrales.
- Nouvelle lecture intégrale Deferral final : 1–471, y compris la catégorie déclarative et tous les corps. La seule modification de ce fichier est l’alignement de la déclaration privée sur le retour BOOL réel.

Le registre de branches initial ci-dessus reste la carte des parcours, pas un héritage de validation ; chacun a été réexaminé sur le contenu final. Les lignes après les changements se décalent de six lignes au total. Le registre des symboles ci-dessous est régénéré à partir de cette version finale et a été rapproché des lectures des corps.

### Corrections et preuves jusqu’au consommateur

**P3-DOC-PDF** : `performAfterRender:` retourne désormais l’acceptation de la requête (NO si handler absent, document fermé ou draft non flushable). Les callers HTML/copie ignorent légitimement le retour faute de delegate externe. Print transmet immédiatement le refus à l’unique `document:didPrint:context:` existant ; ce handler nettoie la session PDF et reprend l’invocation native du delegate avec succès NO. Les branches réussies continuent à attendre le vrai rendu. Aucun second pipeline de nettoyage n’est ajouté. Le test utilise un WebView, une édition contenteditable, une source devenue concurrente et les actions publiques PDF/print ; seul NSSavePanel, frontière d’interaction UI, est contrôlé. Il vérifie slot/URL/tmp, absence de PDF, source et draft préservés, callback exact et nouvel export possible.

**P3-DOC-SETEXT** : chaque titre sélectionné mémorise la fin de l’underline effectivement consommée. La protection de paragraphe examine le premier voisin restant après cette consommation et insère uniquement le séparateur nécessaire avant une ligne susceptible de recréer un Setext. La ligne voisine reste littérale et intacte ; complexité constante par ligne, fins LF/CRLF conservées. Le test preview transforme `Title\n---\n===` en `Title\n\n===` puis vérifie le HTML `<p>Title</p>` réel. Le helper source est corrigé par l’agent renderer pour la même cause dans le même commit métier centralisé.

- RED frais : `build/SquashedPreviewAudit/Pass3/document-red.log`, 2 tests, **9 assertions échouées** (7 PDF, 2 preview Setext), exit 65 ; coffre des préférences restauré et vérifié.
- GREEN frais : `build/SquashedPreviewAudit/Pass3/context-print-green.log`, **22 tests, 0 échec**, 2,405 s ; 2 Lifecycle, classe Deferral entière (19), 1 Utility voisin Setext ; `TEST SUCCEEDED`, coffre restauré et vérifié. Aucun ancien résultat n’est réutilisé comme preuve de cette passe.

### Seconde passe critique finale

Recontrôle de la cause PDF dans tous les callers de `performAfterRender:` et des retours/retains des callbacks ; fermeture reste une annulation explicite des opérations selon son test existant. Recontrôle des voisins Setext après retrait, de la hiérarchie DOM originale et des fins de ligne ; source/editor et preview emploient le même contrat avec leurs preuves Hoedown respectives. Recontrôle des références DOM détenues, des callbacks de génération, des queues popup/native et de leurs garde-fous, de la fraîcheur sauvegarde/autosave, des allocateurs et du throttle watcher. Pas de nouveau défaut confirmé dans ces lectures finales.

Une piste connexe a été **investiguée sans confirmation** : `didFailLoadWithError:forFrame:` vide les handlers et pourrait théoriquement supprimer une completion print. Le rendu propre à l’application charge toutefois exclusivement `loadHTMLString:baseURL:` ; les erreurs CSS/JS/images ne sont pas des erreurs de main-frame, les annulations sont explicitement ignorées, et une connexion HTTP refusée produit une erreur de chargement provisoire plutôt que ce callback. Le parcours hypothétique nécessiterait une navigation principale étrangère pendant l’attente (script local historique / autre contexte) ; aucune chaîne app réelle n’a été établie. Aucun test n’a simulé artificiellement cet appel delegate, aucun correctif spéculatif et aucune garantie supplémentaire sur les scripts locaux de même contexte n’est affirmée. Si une reproduction app établit cette atteignabilité, la piste devra être rouverte ; elle n’est pas comptée parmi les défauts confirmés/corrigés.

## Registre des symboles relus — version finale

Chaque corps, déclaration et helper a été lu dans les plages ci-dessus ; cet index facilite le contrôle de couverture et ne remplace pas cette lecture.

### MacDown/Code/Document/MPDocument.m

```text
46: static NSString *MPNormalizePreviewSelectionText(NSString *text)
53: static NSString *MPPreviewSourceSeparators(NSString *source,NSUInteger start,NSUInteger end)
63: static NSString * const kMPDefaultAutosaveName = @"Untitled";
68: static const NSTimeInterval kMPExternalChangeCoalesceInterval = 0.25;
72: static NSString * const kMPPDFSnapshotJS = @"(function(){var sheets=[];for(var i=0;i<document.styleSheets.length;i++){var sheet=document.styleSheets[i];try{sheets.push(Array.prototype.map.call(sheet.cssRules,function(r){return r.cssText}).join('\\n'));}catch(e){sheets.push(null);}}return JSON.stringify([document.documentElement.outerHTML,sheets]);})()";
74: static NSString * const kMPPreparePDFAnchorsJS = @"(function(args) {\n"
217: static const CGFloat kMPMinZoom = 0.5;
218: static const CGFloat kMPMaxZoom = 3.0;
220: NS_INLINE NSString *MPEditorPreferenceKeyWithValueKey(NSString *key)
229: NS_INLINE NSDictionary *MPEditorKeysToObserve()
247: NS_INLINE NSSet *MPEditorPreferencesToObserve()
271: NS_INLINE NSArray<NSNumber *> *MPDocumentZoomLevels()
281: NS_INLINE NSString *MPRectStringForAutosaveName(NSString *name)
289: NS_INLINE BOOL MPAreNilableStringsEqual(NSString *s1, NSString *s2)
295: NS_INLINE NSColor *MPGetWebViewBackgroundColor(WebView *webview)
311: - (NSString *)absoluteBaseURLString
325: - (NSScrollView *)enclosingScrollView
334: - (int)extensionFlags
364: - (int)rendererFlags
382: static NSString *MPPreviewResourceHTML(NSString *html)
409: - (void)sendEvent:(NSEvent *)event
417: - (BOOL)performKeyEquivalent:(NSEvent *)event
440: - (void)cancelOperation:(id)sender { [self orderOut:sender]; }
451: typedef NS_ENUM(NSUInteger, MPWordCountType) {
459: typedef NS_ENUM(NSUInteger, MPScrollOwner) {
475: typedef NS_ENUM(NSInteger, MPReferenceKind) {
625: - (void)scaleWebview;
626: - (void)syncScrollers;
627: - (void)syncScrollersToCursor;
628: - (void)syncScrollersReverse;
629: - (void)updateHeaderLocations;
630: - (void)validateHeaderLocationAlignment;
632: + (NSArray<NSNumber *> *)editorReferenceKindsForMarkdown:(NSString *)markdown
637: + (CGFloat)previewYForCursorY:(CGFloat)cursorDocumentY
645: + (void)alignEditorYs:(NSArray<NSNumber *> *)editorYs
651: - (BOOL)performAfterRender:(void (^)(void))handler;
652: - (void)invokeRenderCompletionHandlers;
653: - (void)finishPreviewRender;
654: + (NSInvocation *)printCompletionForDelegate:(id)delegate selector:(SEL)selector context:(void *)context;
655: - (void)willStartPreviewLiveScroll:(NSNotification *)notification;
656: - (void)didEndPreviewLiveScroll:(NSNotification *)notification;
658: - (void)refreshHeaderCacheAfterResize;
659: - (void)windowDidEndLiveResize:(NSNotification *)notification;
660: - (void)windowDidChangeFullScreen:(NSNotification *)notification;
661: - (void)applyEditorStartInPreviewModePreference;
663: - (void)handleSyncScrollingEnabled;
664: - (void)handleSyncScrollingDisabled;
666: - (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement preservingSelection:(NSRange)selection;
667: - (void)applyPreviewZoom;
668: - (BOOL)performPreviewFormattingAction:(NSString *)action value:(NSString *)value;
669: - (BOOL)queuePendingPreviewFormattingPayload:(NSDictionary *)payload;
670: - (void)stepDocumentZoomDirection:(NSInteger)direction;
674: - (void)registerSharedPreferenceObservers;
675: - (void)unregisterSharedPreferenceObservers;
677: - (NSUInteger)mathJaxRenderGeneration;
679: - (BOOL)preparePDFAnchorSession;
680: - (void)restorePDFAnchorSession;
681: - (void)postProcessExportedPDFAtURL:(NSURL *)url;
693: static void (^MPGetPreviewLoadingCompletionHandler(MPDocument *doc))()
757: static BOOL MPScanFenceMarker(NSString *line, unichar *outChar, NSUInteger *outLength,
799: - (MPPreferences *)preferences
804: - (NSString *)markdown
809: - (void)setMarkdown:(NSString *)markdown
840: - (NSString *)html
845: - (BOOL)toolbarVisible
850: - (BOOL)previewVisible
855: - (BOOL)editorVisible
860: - (BOOL)needsHtml
869: - (NSString *)wordCountTitleForKey:(NSString *)key number:(NSUInteger)value
877: - (void)applyWordsTitle:(NSUInteger)value selected:(BOOL)selected
884: - (void)applyCharactersTitle:(NSUInteger)value selected:(BOOL)selected
892: - (void)applyCharactersNoSpacesTitle:(NSUInteger)value selected:(BOOL)selected
903: - (void)setTotalWords:(NSUInteger)value
910: - (void)setTotalCharacters:(NSUInteger)value
917: - (void)setTotalCharactersNoSpaces:(NSUInteger)value
924: - (void)setAutosaveName:(NSString *)autosaveName
932: - (NSUInteger)mathJaxRenderGeneration
939: - (instancetype)init
966: - (NSString *)windowNibName
971: - (void)windowControllerDidLoadNib:(NSWindowController *)controller
1112: - (void)registerSharedPreferenceObservers
1123: - (void)unregisterSharedPreferenceObservers
1132: + (NSRange)selectionRange:(NSRange)range clampedToLength:(NSUInteger)length
1150: - (void)setWorkspaceRootURL:(NSURL *)workspaceRootURL
1156: - (void)installFolderSidebarForController:(NSWindowController *)controller
1222: - (void)outerSplitDidResize:(NSNotification *)note
1238: - (BOOL)isSidebarVisible
1246: - (void)showSidebarPane
1275: - (void)hideSidebarPane
1285: - (IBAction)toggleFolderSidebar:(id)sender
1302: - (void)sidebarSyncDidChange:(NSNotification *)note
1327: + (MPDocument *)openDocumentForFileURL:(NSURL *)url
1337: + (NSError *)sidebarOpenErrorForError:(NSError *)error URL:(NSURL *)url
1360: - (void)presentSidebarOpenError:(NSError *)error forURL:(NSURL *)url
1367: - (void)folderSidebar:(MPFolderSidebarViewController *)sidebar
1421: - (void)reloadFromLoadedString
1492: - (void)close
1571: + (BOOL)autosavesInPlace
1576: + (NSArray *)writableTypes
1581: - (BOOL)isDocumentEdited
1592: - (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName
1659: - (BOOL)writeSafelyToURL:(NSURL *)url ofType:(NSString *)typeName
1700: - (BOOL)shouldBypassSafeSaveForURL:(NSURL *)url
1705: - (BOOL)flushPreviewEditorForSaveWithError:(NSError **)outError
1718: - (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
1725: - (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName
1745: - (BOOL)prepareSavePanel:(NSSavePanel *)savePanel
1794: - (NSPrintInfo *)printInfo
1805: - (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)printSettings
1824: - (void)printDocumentWithSettings:(NSDictionary *)printSettings
1850: - (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
1944: - (void)splitViewDidResizeSubviews:(NSNotification *)notification
1975: - (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview
1983: - (NSUndoManager *)undoManagerForTextView:(NSTextView *)textView
1988: - (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
2003: - (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)range
2034: - (BOOL)textViewShouldInsertTab:(NSTextView *)textView
2049: - (BOOL)textViewShouldInsertBacktab:(NSTextView *)textView
2055: - (BOOL)textViewShouldInsertNewline:(NSTextView *)textView
2071: - (BOOL)textViewShouldDeleteBackward:(NSTextView *)textView
2089: - (BOOL)textViewShouldMoveToLeftEndOfLine:(NSTextView *)textView
2121: - (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)dataSource
2138: - (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame
2161: - (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
2169: - (void)finishPreviewRender
2187: - (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error
2208: - (void)webView:(WebView *)webView
2285: - (BOOL)webView:(WebView *)webView doCommandBySelector:(SEL)selector
2304: - (BOOL)previewHasFindFocus
2313: - (BOOL)validateDocumentFindAction:(NSMenuItem *)item
2334: - (IBAction)performDocumentFindAction:(id)sender
2342: - (void)performPreviewFindAction:(NSTextFinderAction)action
2415: - (void)findPreviewText:(NSSearchField *)field
2423: - (void)findPreviewAdjacent:(NSSegmentedControl *)sender
2429: - (NSUInteger)webView:(WebView *)webView
2435: - (NSArray *)webView:(WebView *)sender
2459: - (void)reloadPreview:(id)sender
2468: - (BOOL)rendererLoading {
2472: - (NSString *)rendererMarkdown:(MPRenderer *)renderer
2477: - (NSString *)rendererHTMLTitle:(MPRenderer *)renderer
2486: - (int)rendererExtensions:(MPRenderer *)renderer
2491: - (BOOL)rendererHasSmartyPants:(MPRenderer *)renderer
2496: - (BOOL)rendererRendersTOC:(MPRenderer *)renderer
2501: - (NSString *)rendererStyleName:(MPRenderer *)renderer
2506: - (BOOL)rendererDetectsFrontMatter:(MPRenderer *)renderer
2511: - (BOOL)rendererWrapsCodeBlocks:(MPRenderer *)renderer
2516: - (BOOL)rendererHasSyntaxHighlighting:(MPRenderer *)renderer
2521: - (BOOL)rendererHasMermaid:(MPRenderer *)renderer
2526: - (BOOL)rendererHasGraphviz:(MPRenderer *)renderer
2531: - (MPCodeBlockAccessoryType)rendererCodeBlockAccesory:(MPRenderer *)renderer
2536: - (BOOL)rendererHasMathJax:(MPRenderer *)renderer
2541: - (NSString *)rendererHighlightingThemeName:(MPRenderer *)renderer
2546: - (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html
2749: - (NSURL *)rendererBaseURL:(MPRenderer *)renderer
2781: - (NSURL *)previewSafeBaseURL:(NSURL *)baseURL
2800: - (void)resourceWatcherSet:(MPResourceWatcherSet *)set
2825: - (void)makeWindowControllers
2832: - (void)editorTextDidChange:(NSNotification *)notification
2849: - (void)editorSelectionDidChange:(NSNotification *)notification
2895: - (void)refreshDocumentWordCountTitles
2904: - (void)userDefaultsDidChange:(NSNotification *)notification
2943: - (void)handleSyncScrollingEnabled
2965: - (void)handleSyncScrollingDisabled
2977: - (void)editorFrameDidChange:(NSNotification *)notification
2990: - (void)willStartLiveScroll:(NSNotification *)notification
3005: - (void)willStartPreviewLiveScroll:(NSNotification *)notification
3015: - (void)didEndPreviewLiveScroll:(NSNotification *)notification
3033: - (void)refreshHeaderCacheAfterResize
3043: - (void)windowDidEndLiveResize:(NSNotification *)notification
3051: - (void)windowDidChangeFullScreen:(NSNotification *)notification
3059: - (void)editorBoundsDidChange:(NSNotification *)notification
3074: - (void)didRequestEditorReload:(NSNotification *)notification
3081: - (void)didRequestPreviewReload:(NSNotification *)notification
3088: - (void)previewBoundsDidChange:(NSNotification *)notification
3106: - (void)scheduleReadingProgressUpdate
3115: - (void)observeReadingProgressDocumentView
3131: - (void)readingProgressDocumentDidChange:(NSNotification *)notification
3136: - (void)setupReadingProgress
3188: - (void)updateReadingProgress
3212: - (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
3241: - (IBAction)copyHtml:(id)sender
3259: - (IBAction)exportHtml:(id)sender
3294: - (IBAction)exportPdf:(id)sender
3341: - (BOOL)preparePDFAnchorSession
3368: - (void)restorePDFAnchorSession
3386: - (BOOL)PDFExportSnapshotIsCurrent
3395: - (void)publishPDFDocument:(PDFDocument *)document atURL:(NSURL *)url
3403: - (void)postProcessExportedPDFAtURL:(NSURL *)url
3450: - (IBAction)convertToH1:(id)sender
3457: - (IBAction)convertToH2:(id)sender
3464: - (IBAction)convertToH3:(id)sender
3471: - (IBAction)convertToH4:(id)sender
3478: - (IBAction)convertToH5:(id)sender
3485: - (IBAction)convertToH6:(id)sender
3492: - (IBAction)convertToParagraph:(id)sender
3499: - (IBAction)toggleStrong:(id)sender
3505: - (IBAction)toggleEmphasis:(id)sender
3511: - (IBAction)toggleInlineCode:(id)sender
3517: - (IBAction)toggleStrikethrough:(id)sender
3523: - (IBAction)toggleUnderline:(id)sender
3532: - (IBAction)toggleHighlight:(id)sender
3537: - (IBAction)toggleComment:(id)sender
3542: - (IBAction)toggleLink:(id)sender
3562: - (IBAction)toggleImage:(id)sender
3603: + (NSString *)tableInsertionForContent:(NSString *)content
3671: - (IBAction)insertTable:(id)sender
3700: - (IBAction)toggleOrderedList:(id)sender
3705: - (IBAction)toggleUnorderedList:(id)sender
3711: - (IBAction)toggleBlockquote:(id)sender
3716: - (IBAction)indent:(id)sender
3724: - (IBAction)unindent:(id)sender
3729: - (IBAction)insertNewParagraph:(id)sender
3752: - (IBAction)setEditorOneQuarter:(id)sender
3757: - (IBAction)setEditorThreeQuarters:(id)sender
3762: - (IBAction)setEqualSplit:(id)sender
3767: - (IBAction)toggleToolbar:(id)sender
3772: - (IBAction)togglePreviewPane:(id)sender
3777: - (IBAction)toggleEditorPane:(id)sender
3782: - (IBAction)toggleAutoSave:(id)sender
3788: - (IBAction)toggleInvisibleCharacters:(id)sender
3794: - (IBAction)render:(id)sender
3809: - (void)invalidateStyleCaches
3849: - (BOOL)performAfterRender:(void (^)(void))handler
3872: - (void)invokeRenderCompletionHandlers
3886: - (void)toggleSplitterCollapsingEditorPane:(BOOL)forEditorPane
3924: - (void)applyEditorStartInPreviewModePreference
3945: - (void)setupEditor:(NSString *)changedKey
4088: - (void)adjustEditorInsets
4104: - (void)redrawDivider
4130: - (CGFloat)previewScale
4144: - (CGFloat)zoomMultiplier
4150: - (void)setZoomMultiplier:(CGFloat)zoomMultiplier
4156: - (void)scaleWebview
4165: - (NSFont *)zoomedEditorFont
4174: - (void)applyEditorFontAndParagraphStyle
4205: - (IBAction)zoomIn:(id)sender
4210: - (IBAction)zoomOut:(id)sender
4215: - (IBAction)resetZoom:(id)sender
4220: - (void)applyCurrentZoom
4361: + (NSArray<NSNumber *> *)editorReferenceKindsForMarkdown:(NSString *)markdown
4599: + (void)alignEditorYs:(NSArray<NSNumber *> *)editorYs
4707: - (void)validateHeaderLocationAlignment
4743: - (void)syncScrollers
4851: - (void)syncScrollersToCursor
4920: + (CGFloat)previewYForCursorY:(CGFloat)cursorDocumentY
5006: - (void)syncScrollersReverse
5096: - (void)setSplitViewDividerLocation:(CGFloat)ratio
5123: - (NSString *)presumedFileName
5156: - (void)updateWordCount
5174: static const NSTimeInterval kWordCountThrottleInterval = 0.25;
5176: - (void)scheduleWordCountUpdate
5201: - (BOOL)isCurrentBaseUrl:(NSURL *)another
5209: #define OPEN_FAIL_ALERT_INFORMATIVE NSLocalizedString( \
5215: #define AUTO_CREATE_FAIL_ALERT_INFORMATIVE NSLocalizedString( \
5221: #define AUTO_CREATE_SCOPE_FAIL_ALERT_INFORMATIVE NSLocalizedString( \
5228: - (BOOL)canAutomaticallyCreateLinkedFileAtURL:(NSURL *)url
5239: - (void)openOrCreateFileForUrl:(NSURL *)url
5346: + (NSInvocation *)printCompletionForDelegate:(id)delegate selector:(SEL)selector context:(void *)context
5363: - (void)document:(NSDocument *)doc didPrint:(BOOL)ok context:(void *)context
5418: - (NSDictionary *)previewDraft
5427: - (BOOL)flushPreviewEditor
5440: - (void)saveDocument:(id)sender
5445: - (void)saveDocumentAs:(id)sender
5450: - (void)canCloseDocumentWithDelegate:(id)delegate shouldCloseSelector:(SEL)selector contextInfo:(void *)contextInfo
5460: - (void)installPreviewEditor
5657: - (NSString *)escapePreviewPlainText:(NSString *)text
5670: - (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement
5675: - (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement preservingSelection:(NSRange)selection
5680: - (BOOL)replacePreviewRange:(NSRange)range withString:(NSString *)replacement preservingSelection:(NSRange)selection restoringRange:(NSRange)restoring
5717: - (NSDictionary *)verifiedPreviewSelection:(NSDictionary *)payload
5763: - (BOOL)applyPreviewEditPayload:(NSDictionary *)payload
6083: - (BOOL)queuePendingPreviewFormattingPayload:(NSDictionary *)payload
6122: - (BOOL)performPreviewFormattingAction:(NSString *)action value:(NSString *)value
6138: - (void)handlePreviewEdit:(NSURL *)url
6161: - (NSDictionary<NSString *, NSString *> *)queryItemsByNameForURL:(NSURL *)url
6178: - (void)handleCheckboxToggle:(NSURL *)url
6228: + (NSString *)toggleCheckboxAtIndex:(NSUInteger)index inMarkdown:(NSString *)markdown
6245: - (void)startFileWatching
6290: - (void)stopFileWatching
6302: - (void)handleExternalFileChange
6341: - (void)processExternalFileChange
6385: - (BOOL)shouldPromptBeforeReloadingExternalChanges
6390: - (void)promptForReloadWithExternalChanges
6420: - (void)presentExternalChangeAlertWithCompletion:(void (^)(BOOL shouldReload))completion
6449: - (void)reloadFromDisk
6480: - (void)applyPreviewZoom
6495: - (void)stepDocumentZoomDirection:(NSInteger)direction
6543: - (IBAction)selectDocumentZoom:(id)sender
```

### MacDownTests/MPDocumentLifecycleTests.m

```text
31: - (int)rendererFlags;
43: - (instancetype)init
93: - (void)dealloc
107: - (void)reloadFromLoadedString;
108: - (void)setupEditor:(NSString *)changedKey;
109: - (IBAction)toggleUnderline:(id)sender;
110: - (IBAction)toggleStrong:(id)sender;
111: - (IBAction)convertToH1:(id)sender;
112: - (IBAction)toggleEmphasis:(id)sender;
113: - (IBAction)toggleStrikethrough:(id)sender;
114: - (BOOL)previewHasFindFocus;
115: - (BOOL)textViewShouldMoveToLeftEndOfLine:(NSTextView *)textView;
126: - (BOOL)applyPreviewEditPayload:(NSDictionary *)payload;
127: - (void)installPreviewEditor;
128: - (void)handlePreviewEdit:(NSURL *)url;
129: - (void)setupReadingProgress;
130: - (void)updateReadingProgress;
131: - (void)willStartLiveScroll:(NSNotification *)notification;
132: - (void)willStartPreviewLiveScroll:(NSNotification *)notification;
133: - (void)processExternalFileChange;
134: - (BOOL)performAfterRender:(void (^)(void))handler;
135: - (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html;
136: - (void)resourceWatcherSet:(MPResourceWatcherSet *)set didDetectChangeAtPath:(NSString *)path;
137: - (IBAction)exportPdf:(id)sender;
138: - (IBAction)exportHtml:(id)sender;
139: + (NSInvocation *)printCompletionForDelegate:(id)delegate selector:(SEL)selector context:(void *)context;
140: - (void)document:(NSDocument *)doc didPrint:(BOOL)ok context:(void *)context;
144: - (void)parseMarkdown:(NSString *)markdown;
148: - (pmh_element **)parseText:(NSString *)markdown;
158: - (void)parseAndRenderNow {
172: - (void)parseAndHighlightNow {
176: - (void)clearHighlighting {
179: - (void)readClearTextStylesFromTextView {
190: - (void)document:(NSDocument *)document printed:(BOOL)success context:(void *)context;
193: - (void)document:(NSDocument *)document printed:(BOOL)success context:(void *)context
206: - (instancetype)init
211: - (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html
216: - (BOOL)presentError:(NSError *)error
234: - (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSInteger))completion
240: static MPControlledExportPanel *MPCurrentControlledExportPanel;
241: static id MPControlledExportPanelFactory(id receiver, SEL selector)
256: - (void)setUp
276: - (void)tearDown
293: - (void)testDocumentDirtyFlagAfterEdit
311: - (void)testDocumentDirtyFlagAfterMultipleEdits
325: - (void)testDocumentDirtyFlagAfterUndoRedo
345: - (void)testUntitledDocumentDirtyFlag
365: - (void)testDocumentRevertClearsChanges
393: - (void)testDocumentRevertFromDisk
420: - (void)testDocumentEncodingDetectionUTF8
439: - (void)testDocumentEncodingDetectionUTF8BOM
456: - (void)testDocumentEncodingDetectionASCII
476: - (void)testDocumentWithNoExtension
495: - (void)testDocumentWithUnusualExtension
517: - (void)testSaveWithFileModifiedExternally
549: - (void)testDocumentDetectsExternalChange
579: - (void)testOpenFileDeletedDuringEdit
607: - (void)testDocumentFileURLAfterFileDeleted
631: - (void)testReadableTypes
640: - (void)testWritableTypesForSaveOperation
651: - (void)testAutosavesInPlaceRespectsPreference
670: - (void)testPreservesVersions
681: - (void)testDataOfTypeWithEmptyDocument
694: - (void)testReadFromDataSetsLoadedString
714: - (void)testVeryLongFileName
744: - (void)testSpecialCharactersInFileName
758: - (void)testUnicodeFileName
787: - (void)wireDocument:(MPDocument *)doc
808: - (void)testNewDocumentTriggersRenderOnReload
828: - (void)testNewDocumentTriggersHighlightOnReload
846: - (void)testExistingDocumentClearsHighlightingBeforeReloadHighlight
870: - (void)testExistingDocumentTriggersRenderOnReload
888: - (void)testReloadConsumesLoadedString
905: - (void)testReloadSetsEditorStringFromLoadedString
925: - (void)testReloadIsNoOpWhenDependenciesNotReady
946: - (void)testReloadDoesNotModifyEditorStringForNewDocument
972: - (void)testPreReadyRendersNotBlockedByAlreadyRenderingInWeb
998: - (void)testPostReadyRendersBlockedByAlreadyRenderingInWeb
1024: - (void)testRendersNotBlockedWhenAlreadyRenderingInWebIsNO
1086: - (void)testRendererBaseURLForOpenedFileAvoidsRealDocumentFile
1109: - (void)testWorkspaceRootURLDefaultsToNilAndIsSettable
1118: - (void)testPrintCompletionRetainsDelegateAndDeliversArguments
1137: - (void)testEditorFootnoteParsingFollowsPreferenceAndPreservesMath
1175: - (void)testUnderlineActionKeepsUnderlineMeaningWithExtensionEnabledOrDisabled
1200: - (void)testBackspaceDeletesSelectionWithoutDeletingMatchingPairAroundIt
1219: - (void)testSmartHomeWithSurrogatePairMovesToFirstContentCharacter
1237: - (void)testPDFExportAllowsOnePendingPanelAndCanRetryAfterCancellation
1259: - (void)testAnEarlierSaveTimerCannotReloadWhileTheLatestSaveIsProtected
1289: - (void)testChangedHeadScriptsReloadAndUnchangedHeadPreservesJavaScriptState
1329: - (void)testPreviewFindActionsSearchRenderedTextWithoutChangingMarkdown
1395: - (void)testPreviewFormattingErrorBelongsToSelectionAndDeselectHidesPanel
1436: - (void)testPreviewFormattingInsideWordsUsesMarkdownAndRendersStyles
1500: - (void)assertPreviewBlockSource:(NSString *)source texts:(NSArray<NSString *> *)texts
1507: - (void)assertPreviewBlockSource:(NSString *)source texts:(NSArray<NSString *> *)texts
1559: - (void)testPreviewBlockConversionPreservesBlankSeparators
1568: - (void)testPreviewBlockConversionLeavesUnselectedSourceBetweenParagraphsUnchanged
1575: - (void)testPreviewBlockConversionConsumesSetextUnderlineWithoutTouchingNeighborRule
1587: - (void)testPreviewSetextConversionPreservesCRLFAndStandaloneRules
1596: - (void)testPreviewMixedStylesApplyToAllSelectedCharactersAndPreserveOutsideStyles
1654: - (void)testPreviewEditingChangesOnlyMappedSourceAndRejectsStaleOrInvalidRequests
1959: - (void)testReadingProgressUsesVisiblePaneGeometryAndClampsBoundaries
2038: - (void)testCodeWrappingChangesLayoutWithoutChangingCodeAndExports
2096: - (void)testFirstRealCodeRenderAfterEmptyPreviewLoadsPrismGrammarAndTokens
2154: - (void)testResourceWatcherBurstPublishesOnceAndAnOldWatcherSetCannotPublish
2201: - (void)testHTMLExportReportsWriteFailureAfterRealRenderAndPreservesExistingFile
2248: - (void)testDeferredConsumerSeesCompletedRealMermaidDiagrams
2303: - (void)testDeferredConsumerRestoresLocalHeadAndBaseAfterHTTPNavigation
2364: - (void)testPreviewSetextProofDoesNotConsumeUnderlineAfterATX
2370: - (void)testPreviewControlsPreserveAuthoredIDsAndRunAttributes
2456: - (void)testPreviewParagraphConversionRemovesATXClosingHashes
2464: - (void)testPreviewBlockConversionRespectsActualMarkdownMarkersAndOptions
2484: - (void)testPreviewWrapperConversionRestoresSelectionAcrossRemovedSetextMetadata
2534: - (void)testPreviewPopupQueuesRapidFormattingWithoutReselecting
2636: - (void)testPreviewDraftIsCommittedBeforeSaveAddsTrailingNewline
2687: - (void)testPDFExportRefusedPreviewDraftReleasesSlotAndCompletesPrint
2747: - (void)testPreviewParagraphSetextConversionPreservesFollowingUnderlineLiteral
```

### MacDownTests/MPRenderDeferralTests.m

```text
19: - (BOOL)performAfterRender:(void (^)(void))handler;
20: - (void)finishPreviewRender;
25: - (IBAction)togglePreviewPane:(id)sender;
26: - (IBAction)copyHtml:(id)sender;
27: - (IBAction)exportHtml:(id)sender;
28: - (IBAction)exportPdf:(id)sender;
44: - (void)setUp
53: - (void)tearDown
63: - (void (^)(void))testHandlerBlock
72: - (void (^)(void))testHandlerBlockWithIdentifier:(NSInteger)identifier
87: - (void)testPerformAfterRenderMethodExists
97: - (void)testPerformAfterRenderDoesNotCrashWithEmptyBlock
107: - (void)testPerformAfterRenderHandlesNilBlock
117: - (void)testRenderCompletionHandlersPropertyExists
130: - (void)testVisiblePreviewStillWaitsForFreshRender
155: - (void)testVisiblePreviewQueuesOperation
177: - (void)testPerformAfterRenderQueuesHandlerWhenPreviewHidden
201: - (void)testMultipleHandlersAreQueuedInOrder
225: - (void)testAllQueuedHandlersAreInvoked
281: - (void)testHandlersExecuteInFIFOOrder
311: - (void)testHandlerQueueClearedAfterInvocation
337: - (void)testRapidSuccessiveCallsQueueAllHandlers
355: - (void)testSubsequentOperationsAfterCompletionWork
397: - (void)testPerformAfterRenderWithWindowController
409: - (void)testCopyHtmlUsesDeferralMechanism
427: - (void)testExportHtmlUsesDeferralMechanism
442: - (void)testExportPdfUsesDeferralMechanism
452: - (void)testOldRenderCompletionCannotReleasePendingExport
462: - (void)testCloseCancelsPendingOperations
```


## Complément issu du contrôle Release universel — export HTML / architecture Intel

Le contrôle Release à HEAD `cc358cb` a mis en évidence le cast `controller.stylesIncluded = (BOOL)self.preferences.htmlStyleName`. L’examen frais de toute la chaîne distingue **arm64 (BOOL = bool)** de **x86_64 (BOOL = signed char)**. Sur Intel, convertir directement le pointeur tronque son adresse à huit bits ; une chaîne non nil dont l’adresse termine par 00 devient NO. Le contrat est la présence du style sélectionné, pas une propriété de son adresse.

Dépendances nouvellement lues entièrement : MPExportPanelAccessoryViewController.h/.m, son XIB Base (binding checkbox value → self.stylesIncluded), MPPreferences.h/.m, PAPreferences.h/.m, PAPropertyDescriptor.h/.m, MPUtilities.h/.m. Le getter dynamique NSString est `NSUserDefaults stringForKey:` ; aucun emballage booléen ne protège le cast. L’accessory conserve ensuite le BOOL et le transmet à HTMLForExportWithStyles, qui omet les baseStylesheets ainsi que le CSS d’export quand il reçoit NO. Sur arm64, le même cast bool teste normalement la non-nullité et ne reproduit pas ce défaut.

Régression nouvelle `testHTMLExportIncludesSelectedCustomStyleRegardlessOfStringAllocation` : préférence réelle et 1024 chaînes Foundation longues au maximum, retenues pour observer naturellement une adresse avec octet bas zéro, avec assertion explicite si fixture introuvable. Aucun faux objet, getter remplacé ou pointeur synthétique. Le style CSS UUID correspondant est créé dans le dossier réellement résolu par MPStylePathForName ; seul ce fichier est retiré en finally, et les préférences sont restaurées. Le vrai panneau accessoire/XIB et les vrais renderer/WebView produisent le fichier HTML. Les scénarios vérifient style sélectionné inclus, case volontairement décochée exclue et préférence nil exclue, sans mutation du Markdown. Seule la présentation de NSSavePanel est contrôlée.

**P3-DOC-HTML-STYLES confirmé jusqu’au consommateur** : le premier lancement avec hôte universel et destination x86_64 a passé (1 test, 0 échec), et ne constitue donc pas un RED. La destination seule n’établissait pas l’architecture effective du processus. Un programme Foundation compilé et exécuté explicitement en x86_64 a confirmé la troncature (`OBJC_BOOL_IS_BOOL=0`, octet bas zéro, cast NO, comparaison nonnil YES), puis la racine a forcé `ARCHS=x86_64` pour le vrai test applicatif : `build/SquashedPreviewAudit/Pass3/html-style-intel-forced-red.log`, **1 test, 4 assertions échouées**, exit 65, préférences restaurées. Le diagnostic du test établit l’architecture compilée x86_64 et l’octet bas zéro d’une vraie préférence Foundation. Le défaut est donc un effet applicatif Intel confirmé, et non une simple alerte de compilateur ou un faux objet construit pour le test.

La racine a remplacé uniquement le cast par `self.preferences.htmlStyleName != nil` à la ligne 3268. Le correctif conserve le contrat nil/non-nil, y compris une chaîne vide non nil ; il ne change ni le choix explicite de l’utilisateur dans le panneau, ni le Markdown, ni le pipeline d’export. Les gates finales Intel, arm64, UI et Release restent centralisées par la racine ; aucun résultat non reçu n’est présenté comme vert.

### Nouvelle relecture intégrale après le correctif HTML

- MPDocument.m : **6 562 lignes**, SHA-256 `9c8d4034063cce472c12ba667a81bdcf8c81d013a08dfea61f34763d556cc481`.
- MPDocumentLifecycleTests.m : **2 856 lignes**, SHA-256 `4a10698a13056361e5d1ce454154c19c1a34415f097bd033548fc7b45ddab669`.
- MPRenderDeferralTests.m inchangé : 471 lignes, SHA-256 `4b2bde9d541ac37f404cf6501a97bf8f081c0b5d3dc95d125ec039c92c4033b8` ; sa lecture intégrale finale précédente reste celle de ce contenu identique.
- Document relu intégralement sur le correctif HTML effectif : 1–800, 801–1600, 1601–2400, 2401–3200, 3201–4000, 4001–4800, 4801–5400, 5401–5900, 5901–6562, sorties intégrales. Cela couvre toutes les déclarations, helpers, fonctions, branches et chaînes JS, sans substitution par un diff.
- Lifecycle final relu intégralement : 1–800, 801–1400, 1401–1800, 1801–2200, 2201–2500, 2501–2856. Les diagnostics d’architecture ajoutés ensuite uniquement dans le nouveau test sont inclus dans la lecture finale intégrale 2501–2856. Aucune portion historique du fichier n’a été certifiée sans lecture fraîche dans cette passe.
- Le registre Document ci-dessus reste exact (aucun décalage, modification d’une seule ligne). Pour Lifecycle, l’import MPUtilities.h ajoute une ligne aux anciens symboles ; nouvelle fonction supplémentaire : `2755: - (void)testHTMLExportIncludesSelectedCustomStyleRegardlessOfStringAllocation`. Son corps complet et son finally sont relus.

Seconde passe critique renouvelée : contrat présence de style → checkbox XIB → bool stocké → appel renderer → CSS du fichier HTML consommé ; allocation de vraie préférence, retenue et borne explicite de fixture ; choix utilisateur off et nil ; restauration des IMP, document/WebView et préférences ; retrait du seul fichier de style UUID propre au test. Les autres parcours ont de nouveau été examinés avec leurs garde-fous : fraîcheur draft avant sauvegarde, refus print et unique cleanup/delegate, voisins Setext non sélectionnés, callbacks générations, reload et ressources, mapping/probes bornés, queue native/popup et watcher. Aucun nouveau défaut de production confirmé lors de cette dernière lecture.

Une faiblesse de preuve du nouveau test a été repérée : la garde `if (!styleButton || !panel.completion) return` pourrait sortir sans assertion si la completion est absente. Le bouton est déjà asserté, mais la completion ne l’est pas. La racine est informée ; ajout proposé `XCTAssertNotNil(panel.completion)` avant la garde, après fin de la session Intel courante afin de ne pas mélanger les versions des preuves. Aucun changement concurrent de test n’a été effectué. Le SHA test ci-dessus sera actualisé et le corps relu après cet ajout si retenu.


### Durcissement de la preuve et dernier contenu Lifecycle

La racine a ajouté `XCTAssertNotNil(panel.completion)` avant la garde du nouveau test. L’absence de completion produit désormais un échec explicite, puis le finally restaure la fixture ; aucun succès silencieux n’est possible par cette branche. Nouvelle **lecture intégrale du fichier entier après cet ajout**, sorties non tronquées : 1–800, 801–1400, 1401–1800, 1801–2200, 2201–2500, 2501–2857. Toutes les fonctions historiques, fixtures, branches et assertions du fichier ont à nouveau été lues, au-delà du seul diff.

- Lifecycle final : **2 857 lignes**, SHA-256 `51feffcaf5834c9ad524d2abf48787e2aab453e800ad4571a60d9ab25883c828`.
- Document inchangé : 6 562 lignes, SHA-256 `9c8d4034063cce472c12ba667a81bdcf8c81d013a08dfea61f34763d556cc481`, déjà relu intégralement sur ce contenu.
- Seconde passe test renouvelée : toutes sorties conditionnelles de la nouvelle régression ont une assertion préalable ; real allocation bornée, préférence getter réel, bouton/binding réel et completion réellement consommée ; le choix utilisateur, absence de style et HTML sauvegardé restent vérifiés, avec restauration unique en finally. Aucun nouveau défaut confirmé.

**GREEN native Intel complet** relu dans `build/SquashedPreviewAudit/Pass3/native-intel-full.log` : **1 476 tests, 0 échec, 139,038 s**, `TEST SUCCEEDED`, préférences restaurées et vérifiées. Ce run portait sur le SHA Lifecycle précédent `4a10698a…` (2 856 lignes) et le Document final identique. L’ajout d’une assertion ne change aucune production ; un retest ciblé Intel puis arm64 doit établir le verdict sur le SHA test final. Les gates ciblées finales, UI et Release ne sont pas anticipées dans cette note.

## Clôture centralisée de cette nouvelle passe

Les états intermédiaires ci-dessus sont historiques. Vérifications finales terminées :1476 XCTest complets Intel/Rosetta,13 XCUITest ARM,65 contrats CLI, syntaxe JS, Release universel et signature locale, tous réussis. Test HTML final Intel/ARM après renforcement completion réussi ; aucune modification applicative postérieure aux preuves. Sources finales rapprochées des SHA relus ; tous fichiers modifiés intégralement relus après leur dernière correction et secondes passes terminées. [Clôture et limites](squashed-pass3-cloture.md), [preuves et versions exactes](squashed-pass3-verification.json).
