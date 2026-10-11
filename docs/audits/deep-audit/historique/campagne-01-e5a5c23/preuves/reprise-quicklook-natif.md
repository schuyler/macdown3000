# Quick Look — consommation native isolée finale — 2026-10-07

**Contrat view-based validé**, sans inspection visuelle revendiquée. Le host public QLPreviewView a réellement activé une copie de l’extension finale, son framework et son WKWebView/WebContent ; chargement, commit, finish et premier paint significatif ont été observés. Cette preuve complète les 64 tests du véritable CoreRenderer (HTML exact), les 9 tests du contrôleur (identité/complétion/annulation) et les deux consommateurs sandbox réels préférences/assets.

## Isolation et entrée

Copie de `build/DerivedData/Build/Products/Debug/MacDownQuickLook.appex` dans un host minimal temporaire ; sources/entitlements/framework/principalClass inchangés. Seuls CFBundleIdentifier, UTI et suffixe du fichier ont été rendus uniques, pour éviter toute compétition avec le provider utilisateur. Framework et extension signés ad hoc, politique exacte de `MacDownQuickLook/MacDownQuickLook.entitlements` chargée ; signature host vérifiée strict/deep. Aucun fichier sous /Applications modifié, aucune activation du provider installé, aucun Finder tué/rechargé, aucune sécurité WebKit désactivée.

Dernière identité test : `org.macdown.audit.ql.25b3d26096944fd99fbc0a1b56cb5032.QuickLook` ; UTI `org.macdown.audit.ql.25b3d26096944fd99fbc0a1b56cb5032.markdown` ; fichier `fixture.mdaudit4e5bc179b579460f91bebf4a0e338096`.

Entrée non vide du fichier réellement donné au host :

```markdown
# Native Quick Look identity fixture

Visible paragraph and **bold** text.
```

Aide/man système qlmanage/pluginkit lus ; le consommateur est l’API publique [QLPreviewView de QuickLookUI](https://developer.apple.com/documentation/quicklookui/qlpreviewview), dont le chargement previewItem est asynchrone. Programme `/tmp/macdown-ql-native-view.m` : NSApplication finishLaunching, QLPreviewView dans une fenêtre 800×600, previewItem NSURL du fichier synthétique, run loop 6 s, close et fermeture de sa seule fenêtre. Pilote `/tmp/macdown-native-ql-elected-probe.py` : copie/signe/enregistre, élection temporaire use **uniquement** de notre UUID, appel host puis finally ignore/retrait exact/LSunregister/suppression.

## Preuve positive

`/tmp/macdown-native-ql-elected-probe.log` montre le provider UUID choisi `+`, sa version finale `3000.0.7-rc.1.post171`, le chemin exact du host temporaire et les signatures réussies. `/tmp/macdown-native-ql-xpc.log` lie l’image temporaire au processus **MacDownQuickLook PID 82842** ; le journal filtré exclusivement sur ce PID, `/tmp/macdown-native-ql-extension.log`, montre :

- bootstrap extension et contexte natif host établis ;
- WKWebView `WebPageProxy::loadData/loadDataWithNavigation`, puis **WebContent PID 82847**, pageProxyID 5 / webPageID 6 ;
- `didCommitLoadForFrame`, `didFinishLoadForFrame` et main frame load completed ;
- `DidFirstVisuallyNonEmptyLayout` et `DidFirstMeaningfulPaint` (lignes 582–645) ;
- annulation du contexte lorsque le host temporaire ferme, pas un échec de chargement de sa page.

Le binaire final du contrôleur ne charge son HTML que si renderMarkdownFromURL réussit ; l’entrée Markdown non vide et les marqueurs de layout/paint attestent donc l’activation, l’accès fichier du host et la consommation WK réelle. L’oracle exact sur le contenu HTML est fourni par Core64 et les tests renderer, complétés par RA01 dans le véritable sandbox. Aucun mock n’a remplacé WKWebView dans cette sonde native.

## Limites explicites

qlmanage `-p -x -c UTIunique -o dossier` retourne exit0 mais « did not produce any preview » et aucun fichier : ce résultat ne certifie pas une preview view-based et n’est pas utilisé comme oracle positif. La capture NSView cacheDisplay ne capture pas le contenu distant (image noire) ; displayState est opaque/nil et les objets AX distants ne fournissent pas une extraction lisible dans ce host. Aucune inspection visuelle du titre/gras ni activation de Finder directement n’est revendiquée. La validation porte sur le contrat view-based source (activation/contexte/fichier/HTML→WK load/finish/paint), dans un provider isolé ad hoc ; ce n’est pas une signature de distribution Developer ID.

## Nettoyage

Enfin élection UUID remise à ignore (`-` observé), pluginkit -r du seul chemin temporaire, lsregister -u du seul host temporaire ; requête exacte UUID retourne **no matches**. Répertoire temporaire supprimé et absence vérifiée. Provider utilisateur installé non touché. `/tmp/macdown-native-ql-cleanup.log` confirme la suppression des fichiers ordinaires de nos quatre containers ; seules métadonnées ContainerManager macOS protégées restent, sans permissions forcées :

- `/Users/zydon/Library/Containers/org.macdown.audit.ql.1b6a65af23f44b598dd9640aca345c81.QuickLook`
- `/Users/zydon/Library/Containers/org.macdown.audit.ql.48ed745637b24c1c91349e7387a2cd33.QuickLook`
- `/Users/zydon/Library/Containers/org.macdown.audit.ql.92288fa610c34c6a95a6b27a7414778d.QuickLook`
- `/Users/zydon/Library/Containers/org.macdown.audit.ql.25b3d26096944fd99fbc0a1b56cb5032.QuickLook`

## Décision par fichier

PreviewViewController.h et .m : **validables** selon leurs interfaces/lifecycle/policy et contrat natif de chargement/paint, lectures intégrales finales + Controller9/Core64 + activation réelle ci-dessus. Info.plist QuickLook : **validable** pour principalClass/extension point/version/UTI metadata compilés et activation de la même extension, identité/UTI synthétiques uniquement pour isolation. Les associations Finder de l’identité utilisateur n’ont pas été changées ni prétendument testées.
