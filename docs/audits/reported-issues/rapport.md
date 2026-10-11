# Vérification des signalements upstream — 8 octobre 2026

## Périmètre et baseline

Demande : séparer les bugs des demandes de fonctionnalités/thèmes, vérifier les bugs sur notre code actuel et corriger uniquement les défauts confirmés. Méthode : `external-audit`. Baseline locale `ac99569`, clôture de la campagne 03, source `c0cd3a1`. Branche `codex/reported-bugs`. Cette passe est ciblée ; elle ne renouvelle pas la certification exhaustive de l’inventaire historique.

Environnement réellement exercé : macOS 26.6.2 (25G83), Apple Silicon, Xcode 26.2. Les versions 3000.0.6, 3000.0.7 et 3000.0.8-rc.1 des signalements ne sont pas toutes retestées. Les tests portent sur le dépôt actuel. Les builds de test compilent arm64 et x86_64 ; les tests s’exécutent sur arm64. Pas de validation d’exécution Intel ou sur une autre version de macOS.

Les tests XCTest et XCUITest utilisent une session privée, avec préférences et données d’application sauvegardées puis restaurées et comparées par le coffre de test. L’application installée dans `/Applications` n’est pas remplacée. Aucun choix global d’application par défaut n’est modifié. Les premiers essais de fixtures imparfaites ne servent pas de preuves de défaut.

## Delta vs baseline

- **Nouveau : 3 défauts confirmés** (#575, #584, #589).
- **Réouvert : 1 défaut confirmé** (#594).
- **Connu assumé : 0**.
- **Effectivement corrigé : 4**, avec un commit distinct par correction.
- **Non confirmé : 1** (#586, perte de document jamais enregistré).
- **Partiellement confirmé, non résolu : 1** (#587, icône Finder).
- **Demandes différées : 6**, hors corrections de cette passe.

La campagne antérieure avait considéré le rafraîchissement des scripts comme corrigé (`f49e6a3`, test `21828e9`). Son test couvrait des scripts placés dans le head. Le gabarit réel place aussi les composants Prism à la fin du body : cette condition n’était pas couverte. #594 est donc réouvert. Le code de la baseline initiale `e5a5c23` comparait déjà uniquement le head ; ce défaut préexistait à nos corrections, qui ne l’avaient pas entièrement réparé.

## Corrigé

| Issue | Validation / suivi | Preuve avant correction | Correction / commit | Vérification après correction |
|---|---|---|---|---|
| [#575](https://github.com/schuyler/macdown3000/issues/575) — titres multilignes trop serrés | Confirmé / Nouveau | WebView réel : GitHub H1, taille 22,68 px / interligne 18,68 px ; H2, taille 20,01 px / interligne 18,68 px. Les deux échouent au contrôle d’espacement. | `2126eb5` : `GitHub.css`, interligne des H1–H6 à 1,25 fois leur propre taille. | 66 titres, 11 styles intégrés, zéro échec. Le test natif autonome est ajouté à la CI. Les CSS personnalisées ne sont pas réécrites. |
| [#584](https://github.com/schuyler/macdown3000/issues/584) — Cmd-F dans l’aperçu | Confirmé / Nouveau | XCUITest réel : clic dans le WebView, Cmd-F, absence d’interface de recherche. | `8083242` : routage des cinq actions Find vers le document/panneau actif ; panneau de recherche en lecture seule utilisant la sélection et la recherche natives du WebView. La recherche et le remplacement du source restent natifs. | Texte rendu réparti sur plusieurs nœuds HTML et accentué, suivant/précédent, sélection, Markdown inchangé ; UI Cmd-F, Cmd-G, Maj-Cmd-G, Échap, retour à Find côté source. Le presse-papiers de recherche est restauré après les tests. |
| [#589](https://github.com/schuyler/macdown3000/issues/589) — dossier déposé sur l’application | Confirmé / Nouveau | Le delegate n’a pas de consommateur `application:openURLs:` pour router les dossiers vers le workspace. Test rouge sur l’entrée publique. | `df34d27` : les vrais dossiers passent par `openWorkspaceAtURL:` ; les fichiers et packages passent par NSDocumentController. | Lot mêlant deux dossiers, chemins Unicode et fichier Markdown : racines de workspace et contenu du document vérifiés. Suite folders : 8 tests, zéro échec. Il n’y a pas de seconde implémentation de workspace. |
| [#594](https://github.com/schuyler/macdown3000/issues/594) — Prism absent au premier chargement | Confirmé / Réouvert | MPDocument + MPRenderer + WebView réels : rendu vide puis JavaScript fenced ; absence de grammaire/tokens avant correction. | `f4a7ef1` : signature des ressources comprenant le head et toutes les balises script, y compris celles du body. Rechargement complet si cette signature change ; remplacement rapide du body si elle reste identique. | Le composant `Prism.languages.javascript` est chargé et produit des `span.token` dès le premier contenu. Le test existant de head changé et d’état JavaScript conservé avec head inchangé passe aussi. |

Fichiers de production modifiés : `MacDown/Resources/Styles/GitHub.css`, `MacDown/Code/Application/MPMainController.m`, `MacDown/Code/Document/MPDocument.h`, `MacDown/Code/Document/MPDocument.m`, `MacDown/Localization/Base.lproj/MainMenu.xib`. Les tests associés sont dans `MPMainControllerFolderTests.m`, `MPDocumentLifecycleTests.m`, `MacDownUITests.swift` et `BuildTools/heading_spacing_tests.{m,py}`.

## Non corrigé

### #586 — document jamais enregistré perdu après quitter/relancer

**Non confirmé sur le code actuel.** NSDocument déclare déjà l’autosauvegarde des brouillons et la restauration. Le test natif utilise un vrai document sans URL, une modification avec groupe undo clôturé, puis l’autosauvegarde AppKit ; l’emplacement de récupération contient exactement le texte accentué et japonais attendu.

Le test UI crée explicitement un document avec Cmd-N, vérifie qu’il est vide, saisit un identifiant unique, quitte normalement avec Cmd-Q puis relance l’application avec restauration activée. Le contenu est retrouvé dans l’une des fenêtres restaurées. Un second test contrôle le même cycle pour un fichier existant modifié. Les deux passent. Le commit `dd59dd8` ajoute cette couverture sans modifier le comportement de production.

Limite : ces tests activent `editorAutoSave` et la conservation des fenêtres. Ils ne prouvent pas la restauration avec ces options désactivées, ni après crash/arrêt forcé, ni sur toutes les anciennes versions citées. Si le défaut est encore observé, collecter les réglages exacts et reproduire sur la même révision avant d’altérer le cycle de vie AppKit.

### #587 — icône Word sur les fichiers Markdown

**Partiellement confirmé ; aucune correction annoncée.** Le bundle MacDown déclare uniquement le type historique `net.daringfireball.markdown`. Word installé déclare `public.markdown`, avec son icône et un rang Default. La lecture des associations LaunchServices donne ici :

- `net.daringfireball.markdown` → MacDown ;
- `public.markdown` → Word ;
- le fichier `.md` témoin est typé `com.unknown.md`, avec Notion comme application d’ouverture ; son icône NSWorkspace est visuellement celle de Word.

Le symptôme d’icône est observé, mais cette machine n’a pas le même état « MacDown ouvre effectivement tous les .md » que le signalement : un troisième type intervient. Ajouter une déclaration importée ne garantit pas de gagner l’arbitrage Finder, comme le précise déjà le rapport fourni. Modifier un rang à Owner ou imposer des associations serait spéculatif et pourrait remplacer le choix de l’utilisateur. Aucun changement de ce type n’a été appliqué.

Suite nécessaire : une reproduction contrôlée avec build de distribution signé, MacDown comme application par défaut effective, puis vérification Finder de chaque type après choix explicite du handler. La compatibilité des deux UTIs peut ensuite être traitée avec preuve du résultat visible, sans annoncer qu’une déclaration plist seule résout le défaut.

### Fonctionnalités et thèmes différés à la demande de l’utilisateur

| Issue | Nature | Demande |
|---|---|---|
| [#573](https://github.com/schuyler/macdown3000/issues/573) | Fonctionnalité | Option de retour à la ligne dans les blocs de code longs. |
| [#576](https://github.com/schuyler/macdown3000/issues/576) | Fonctionnalité | Choisir une apparence sombre/claire indépendante de macOS. |
| [#581](https://github.com/schuyler/macdown3000/issues/581) | Fonctionnalité | Indicateur de position de lecture en pourcentage. |
| [#588](https://github.com/schuyler/macdown3000/issues/588) | Thèmes / documentation | Ajouter ou référencer les thèmes de mfeilen. |
| [#590](https://github.com/schuyler/macdown3000/issues/590) | Fonctionnalité | Mode lecteur ou préférence de visibilité de l’éditeur pour plusieurs documents. |
| [#596](https://github.com/schuyler/macdown3000/issues/596) | Fonctionnalité | Prise en charge de fonctionnalités Quarto, notamment les callouts. |

Aucune implémentation ou intégration de ces six demandes dans cette passe.

## Vérification de livraison

Les résultats finaux et empreintes de fichiers sont enregistrés dans `verification.json`. Les journaux et xcresult bruts restent localement dans `build/ReportedBugs` et `build/AuditCampaign03/Logs/Test` ; ils ne sont pas versionnés. Les tests rouges ciblés sont distingués des essais exploratoires de fixtures qui ne constituent pas des régressions de production.

La suite native complète comprend 1 441 tests, zéro échec. Le contrat WebView des titres comprend 66 contrôles, zéro échec. La suite UI complète comprend les quatre tests historiques plus recherche et deux scénarios de restauration ; elle passe avec 7 tests et zéro échec. Aucun job GitHub distant n’a été exécuté pour cette branche. Ces commits ne sont pas encore intégrés à la PR antérieure #597.

## Registre des risques assumés

Aucun point classé `Connu assumé`. Le conflit d’icône demeure ouvert avec validation partielle ; il n’est ni masqué ni déclaré corrigé. La restauration n’est pas certifiée pour des réglages ou versions non exercés.
