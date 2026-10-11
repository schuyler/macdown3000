# RA01 — styles utilisateur QuickLook dans le sandbox

Défaut prouvé par `quicklook-custom-assets-candidat.md` : container ApplicationSupport différent du dossier utilisateur app, et lecture hors container refusée sans entitlement dédié. Correction autonome de ces deux causes ; aucune modification des renderflags, du préprocesseur, du projet ou des chemins PDF/UI.

`MPQuickLookUserAssetRoot` résout le home réel avec `getpwuid_r`, buffer qui croît sur ERANGE jusqu'à 1 MiB puis fallback nil. Ses deux consommateurs style/thème conservent priorité utilisateur puis bundle et mêmes extensions/noms. La racine correspond au contrat existant de la principale : ApplicationSupport utilisateur + CFBundleName `MacDown 3000` (`MPUtilities.m:20–41`, produit Release du projet). Aucun second stockage ni pipeline alternatif ajouté. Le helper est partagé par les deux consommateurs Core ; la principale hors sandbox garde sa résolution Foundation valide.

L'entitlement QuickLook accorde uniquement les deux répertoires home-relative Styles et Prism/themes en lecture, slash initial/final conformément à la [documentation Apple](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html). L'exception shared-preference demeure exacte et séparée, aucun accès global ApplicationSupport/Library ni écriture ajouté.

## Vérification

`python3 MacDownTests/Sandbox/assets_tests.py` passe : compilation du **véritable CoreRenderer**, de ses préférences et des sources hoedown réelles, signature de bundles sandbox ad hoc avec les entitlements production réellement chargés. Le test n'extrait ni ne recopie les fonctions de résolution. Il appelle la méthode publique `renderMarkdown:@"# Isolated asset fixture"` et vérifie le titre h1 réellement rendu ainsi que les CSS présents dans le HTML. La sous-classe fixture remplace les trois getters de styling et les deux getters de flags par des constantes ; elle est installée par KVC comme les tests XCTest existants. Le singleton réel est construit sans lecture des clés utilisateur. Lors des premiers essais, seuls les getters styling étaient remplacés et le corps Markdown était vide : la branche return wrapBodyInHTML précédait preprocess/parse, donc extensionFlags/rendererFlags n’étaient pas appelés. Ces méthodes restaient héritées et auraient lu les bools utilisateur avec un corps non vide (sans écriture) ; la relecture du coordinateur a identifié ce risque d’isolation. Les overrides éliminent maintenant ce risque et le test final exerce un Markdown non vide. Aucun seam production n'a été ajouté.

- Grant retiré dans la fixture négative : absence des marqueurs USER dans le HTML.
- Entitlements production : marqueurs du style **et** du thème utilisateur présents, même si des CSS différents du même nom existent dans le bundle.
- Après suppression des deux fixtures utilisateur : fallback bundle présent pour les deux CSS.
- Écritures dans les deux répertoires autorisés et dans le voisin non autorisé refusées ; lecture de ce voisin refusée. Contenus des fichiers vérifiés inchangés avant suppression.
- Mutant avant correction : source Core de HEAD compilée sous `/tmp` (seul chemin import ajusté), même pilote/noms/entitlements ; échec `Missing CSS USER_STYLE`, alors que la version corrigée passe. Cela distingue la résolution home, indépendamment du seul ajout de permission.
- Chaque subprocess est borné à30s et son groupe est tué sur timeout. `plutil -lint` entitlement passe. Aucun Xcode lancé.

Premier essai de fixture négative attendait à tort un fallback bundle quand un fichier existe mais est refusé à la lecture ; cette assertion n'était pas le contrat du helper et a été remplacée par absence du CSS USER. Le test final vérifie séparément le véritable fallback quand les fichiers utilisateur sont absents. Aucune correction production justifiée par cette attente erronée.

## Lecture finale

Renderer final complet relu sans troncature en plages 1–200 puis 201–fin (372 lignes), entitlement et les deux nouveaux tests entièrement relus après dernier changement. SHA-256 :

| Source | SHA-256 |
| --- | --- |
| `MacDownCore/MPQuickLookRenderer.m` | `ac4f7b28b7d77d98b4544ee71387018480f60ab0b1465993fe1d520e0c79a747` |
| `MacDownQuickLook/MacDownQuickLook.entitlements` | `2c615c485eaf437fe2b7c497741bc6fbae2dbba627db9fe590703f3fc2097f9a` |
| `MacDownTests/Sandbox/assets_contracts.m` | `96e206c0faa932f9736899303bf314004113283c947f58f55ff10a7ba90e68f6` |
| `MacDownTests/Sandbox/assets_tests.py` | `0ef555c7b7bc300ffb9f3af6dcea5469f8c687c397519989ec3d17f0f55d0c2b` |

Limites : consommateur Core réellement sandboxé, pas lancement Finder/PreviewViewController ni distribution Developer ID. Le gate produit final appartient au coordinateur. Les CSS UUID uniquement sont supprimés en finally ; les dossiers créés par le test sont retirés s'ils restent vides. Métadonnées de containers protégées par macOS : pas de permissions forcées. Containers restants des essais supplémentaires (sous `/Users/zydon/Library/Containers/`) : `org.macdown.audit.assetreader.ed7e073f3ebe414f8c5539898826a476.denied`, `org.macdown.audit.assetreader.0089f621e8494923be85f19eb01d2d82.denied` et `.granted`, `org.macdown.audit.assetreader.d7b56bbb0ec54c989efc03a766d1d1fc.denied` et `.granted`, `org.macdown.audit.assetreader.43bdd542a4134f1daeb3b9143268c77b.denied` et `.granted`. Les deux containers de la preuve initiale restent consignés dans celle-ci.

Après revue du coordinateur, le test final non vide est vert ; le mutant ancienne résolution est à nouveau rouge `Missing CSS USER_STYLE`. Fixture finale intégralement relue après les deux overrides et l’assertion h1. Le coordinateur rapporte build workspace scheme MacDownQuickLook Release universel réussi (`/tmp/macdown-audit-quicklook-release2.log`) ; cela compile les sources QL mais ne certifie pas les modifications PDF intermédiaires du host implicitement inclus.

Containers de ces derniers runs, sous `/Users/zydon/Library/Containers/` (métadonnées protégées, aucun vrai fichier utilisateur résiduel) : `org.macdown.audit.assetreader.7c6a42bb206148dea8979bcf6f2d9ce5.denied` et `.granted`, `org.macdown.audit.assetreader.2241fcfd364a42919b28b9ecf33509d2.denied` et `.granted`, `org.macdown.audit.assetreader.37fc7283cf604f48b07cdcf6dc60b845.denied` et `.granted`, `org.macdown.audit.assetreader.5b6bca20eff54a3b9b8eda27abb9f7f3.denied` et `.granted`.
