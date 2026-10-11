# Quick Look — lecture réelle des préférences en sandbox — 2026-10-07

**RS01 confirmé et corrigé.** CFPreferencesCopyValue(CurrentUser,AnyHost) ne donne pas automatiquement à une extension sandboxée accès au domaine principal MacDown. La politique de l’extension ne contenait aucune exception partagée ; le commentaire affirmait à tort que lecture CFPreferences suffisait. Entitlement read-only ajouté uniquement pour `app.macdown.macdown3000`, commentaire corrigé. Aucun accès en écriture ajouté.

## Preuve réelle, sans seam sandbox

- Sonde initiale : même lecteurCFPreferences, binaries apps signés ad-hoc avec app-sandbox ; valeur préalablement écrite dans UUIDdomain synthétique. Hors sandbox valeur lue ; sandbox sansexception NULL/exit1 ; ajout exception domaineexact valeur lue/exit0. Aucun vrai domaine MacDown lu ou écrit.
- Test final `python3 MacDownTests/Sandbox/preferences_tests.py` : exit0. Charge le fichier d’entitlement réel du projet et exige exactement array `[app.macdown.macdown3000]`, refuse read-write. Copie politique réelle, remplace uniquement domaineapp par UUIDfixture. Variante témoin retire read-only exception :NULL ; variante corrected signée adhoc :valeur synthetic consommée. Vrai CFPreferences daemon/signature/AppSandbox, aucune permission simulée.
- Tentative écriture avec exceptionlectureseule : CFPreferencesSynchronize false (harness exit2), puis lecteur nonsandbox retrouve originalsynthetic intact. Initial assertion du test attendait synchronisation0 ; run interrompu malgré readcontracts verts, corrigé pour exiger véritable refus2 (pas suppression de test). Run final vert inclut ce refus et valeur partagée inchangée.
- Cleanupfinally supprime seule clé fixture et synchronize, lecteur confirme absence. Apps et entitlements temporaires supprimés. Native harness refuse domaine ne commençant pas org.macdown.audit.preferences. Pas de préférence utilisateur/appMacDown concernée.
- Chaque compilation/signature/lectureécriture subprocess borné15s, groupeprocess tué surtimeout. Aucun Xcode/releaseidentity modifié.

## Limite de nettoyage macOS constatée

macOS refuse suppression des métadonnées protégées ContainerManager des apps synthétiques, après suppression des fichiers ordinaires. Permissions personnelles conservées ; aucun contournement exécuté. Ces six répertoires de fixtures peuvent rester avec métadonnées seules :

- `/Users/zydon/Library/Containers/org.macdown.audit.reader.6d18760de6af4cd1bd03d4f568e1eb07.denied`
- `/Users/zydon/Library/Containers/org.macdown.audit.reader.6d18760de6af4cd1bd03d4f568e1eb07.granted`
- `/Users/zydon/Library/Containers/org.macdown.audit.reader.2f5a886811644062b4f2f065a80ac783.denied`
- `/Users/zydon/Library/Containers/org.macdown.audit.reader.2f5a886811644062b4f2f065a80ac783.granted`
- `/Users/zydon/Library/Containers/org.macdown.audit.reader.23a41ca9985f4f2d872d0706e875c97f.denied`
- `/Users/zydon/Library/Containers/org.macdown.audit.reader.23a41ca9985f4f2d872d0706e875c97f.granted`

Première sonde : cleanup première erreur arrêtait la boucle, secondcontainer peut contenir ses données par défaut sans valeurutilisateur ; testfinal traite chaquecontainer et trace limites exactes. Aucune suppression administrative nécessaire à preuve readcontract ; résidu déclaré distinctement du succèsfonctionnel.

## Lecture complète finale et empreintes

| Chemin | SHA-256 | Lu | Analysé | Validé | Preuve spécifique |
| --- | --- | --- | --- | --- | --- |
| `MacDownQuickLook/MacDownQuickLook.entitlements` | b625a38499d888ac947a33bfd66a2725aa6b4a766532cb4f9cca2b47b7eaf1b8 | ☑ | ☑ | ☐ | Toutes clés sandbox/network/files et seule exceptionread-only domaineexact ; plist chargé/test réel avec policycopiée ; signatureextension produitfinal gate root. |
| `MacDownCore/MPQuickLookPreferences.m` | e269e6e827ef42f6082cd7ea9f8943ad16c04976badb9bbaf41a6deb8de5113e | ☑ | ☑ | ☐ | Entire singleton/helpers typechecks/string/defaultbool, style/highlight/syntax keys, flags extensions et renderer flags, diagramdisables ; commentairelié politique. ValeursCFPreferences réelles consommées harness ; APIs QuickLook intégrées gate root. |
| `MacDownTests/Sandbox/preferences_contracts.m` | 10a9a61f61ae6dd07e20895e7b4e436658e4107c8597f99efad45790c4a33e44 | ☑ | ☑ | ☐ | Tout main : argc/domainprefix refus, writer/delete synchrostatus, read CFBridgingRelease/compareexit ; exécuté réelaveclecture/refuswrite/cleanup. |
| `MacDownTests/Sandbox/preferences_tests.py` | e3ed72fd1e9995a61689242cae7a9599636f41d000801e9dd6ca718e4370380b | ☑ | ☑ | ☐ | Tout fixture runner/isolation/domain UUID/policyactual copy/assertscope/sign adhoc/expected statuses/finallytimeouts et cleanup exceptionreport : exécutévert. |

Commit autonome : les deux sources + les deux fichiers de test Sandbox. Tous relus intégralement après dernière modification. Aucun `Validé` global : chargement extension finale/signaturebundle root et donnéesstyles user overrides distincts.
