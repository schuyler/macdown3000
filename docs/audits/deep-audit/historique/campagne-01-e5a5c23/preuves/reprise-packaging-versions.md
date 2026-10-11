# Reprise packaging — versions app et extension

## RV01 — métadonnées cohérentes avant signature

Défaut confirmé par le build Release réel du coordinateur : `/tmp/macdown-audit-clean-release.log:12618`, validation du binaire embarqué, `CFBundleVersion` de QuickLook `0` contre application `1556`. Les plists sources des deux produits emploient `CURRENT_PROJECT_VERSION` et `MARKETING_VERSION`, dont les valeurs locales initiales sont `0` et `0.0.0-dev`. Seule la cible application exécutait `Tools/update_build_number.sh` ; l'extension conservait donc les valeurs initiales pour les deux versions.

Correction limitée au projet : nouvelle phase finale **Update Build Number** sur la cible QuickLook, appelant exactement le même helper que l'application avec son propre `TARGET_BUILD_DIR/INFOPLIST_PATH`. L'extension reçoit ses métadonnées avant sa signature et son incorporation ; aucune modification de son plist embarqué après signature. Le calcul Git reste une implémentation unique dans `Tools/utils.sh`. Le comportement CI est conservé : l'action composite fournit les versions comme paramètres globaux Xcode et le helper ignore volontairement `CI=true`.

Un commit indépendant doit inclure uniquement le hunk de phase QuickLook dans le projet, `MacDownTests/BuildTools/packaging_version_tests.py` et cette preuve.

## Vérifications observables

- Nouveau test rouge avant correction : absence de phase version propre à QuickLook.
- `python3 MacDownTests/BuildTools/packaging_version_tests.py` vert : lecture du véritable projet avec `plutil`, exécution des deux véritables scripts de phase dans un dépôt Git isolé avec chemins contenant des espaces ; compilation de deux Mach-O, signature ad hoc de l'extension, incorporation dans l'app puis mise à jour du parent. Les plists consommés donnent tous deux `CFBundleVersion=2` et `CFBundleShortVersionString=2.3.4.post1` ; l'extension embarquée reste identique et `codesign --verify --strict` passe. La phase QuickLook ne touche pas le plist du parent. Les valeurs CI explicites `987` / `9.8.7` sont préservées byte pour byte par les deux phases.
- `python3 MacDownTests/BuildTools/version_tests.py` vert : calculs Git, dates du header, consommateur C réel et erreurs plist.
- `plutil -lint 'MacDown 3000.xcodeproj/project.pbxproj'` : OK.
- Aucun Xcode concurrent lancé par cet agent. Le build Xcode final réel et la disparition du warning restent le gate du coordinateur ; le test autonome ne certifie pas ce gate.

## Lecture et empreintes

Lecture intégrale finale du nouveau test, du helper, de `Tools/utils.sh`, de l'action composite et des deux plists sources. Projet final **2909 lignes entièrement relues**, après la correction, par plages contiguës sans troncature : 1–150, 151–300, 301–380, 381–460, 461–540, 541–620, 621–700, 701–800, puis 801–1100, 1101–1400, 1401–1700, 1701–2000, 2001–2300, 2301–2600, 2601–2900, 2901–2909. Les références sources/frameworks, groupes, variantes locales, ressources, six cibles natives et la cible agrégée, phases et dépendances, configurations et listes finales ont été examinées ; le parcours de version reste commun aux deux produits. L'empreinte après cette lecture est identique à celle du patch testé. La première tentative tronquée a été écartée et remplacée par ces lectures complètes. Aucune case de validation générale ni ligne d'inventaire modifiée par cet agent.

| Fichier | SHA-256 après correction | Portée de lecture |
| --- | --- | --- |
| `MacDown 3000.xcodeproj/project.pbxproj` | `bb83fc2aec277b6160ab5d1c08c66da113e5e006edb88ff09fd44386557f55f4` | intégrale finale, 2909 lignes |
| `Tools/update_build_number.sh` | `633982df9b4deac8de1361bc590a76c6f471ba9d09686b2e3e22f9d83165374c` | intégrale, inchangé |
| `Tools/utils.sh` | `6fa173ed0679ea1d15888e72323d025023e9b04e624020925b6cf819852df921` | intégrale, inchangé |
| `MacDownTests/BuildTools/packaging_version_tests.py` | `1cc88177ac142cc3621de4c43c01e8b9aec8c58169e467bc88874b51dee0f97a` | intégrale |
