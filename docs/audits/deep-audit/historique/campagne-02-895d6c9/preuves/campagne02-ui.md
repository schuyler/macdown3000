# Campagne 02 — UI et locales (lecture complète)

Baseline `e5a5c237b92d172e953abf0680869ad0a5b4806f` ; 7 octobre 2026.
Lot exclusif `lots/ui-locales.json` : 304 fichiers, composé de 32 sources Objective-C,
47 manifestes assets, 8 XIB et 217 strings. Aucune ancienne case ou ancienne note
d'audit copiée. Les tests existants consultés servent uniquement à identifier
les contrats ; leur exécution campagne 02 appartient à root.

**304 lus, analysés et validés manuellement dans les contrats examinés.**
Chaque chemin est attesté manuellement après affichage complet et analyse dans
`campagne 02-ui.json`. Les contrôles programmatiques ne remplacent pas ces lectures.
La lecture et la seconde passe du lot sont terminées. Les gates AppKit/bundle
initialement ouvertes ci-dessous sont clôturées par les preuves finales en fin de note.

## Parcours et preuves

- Sources des préférences : init/migrations legacy/version et suite handoff ;
  bindings flags, nombres avec formatters, font/theme/CSS/prism choix et reload,
  resizabilité/checkboxes wrapping/timing toolbar et teardown responder.
- Terminal : discovery weak callback main queue relisant le FS courant ;
  créations/réparations symlink, source/dir/erreurs, PATH, ownership avant unlink,
  changement UI installé/non installé et highlight borné.
- Toolbar : factories/identifiants/actions/groupes, sélection bornée, dispatch
  lazy document faible, dropdown validation synchrone/restauration, zoom KVO.
- Sidebar : lazy disk tree et symlink ancestor cycle, links broken/hidden exclus,
  activation consommant resolvedURL, reload selection/expansion, observer/stream
  stop lifetime, sharing root/equality no-op, drag flag @finally et frame sizing.
- Vues : ratio resize/swap deux sous-vues établi par nib ; pasteboard interop,
  paste link escaping/scheme, drag inlining, trailing layout et substitutions.
- 8 XIB entiers lus en plages contiguës avec reprise des sorties tronquées :
  toutes entrées, actions, outlets, bindings, formatters, contraintes, ressources,
  fenêtres, Touch Bar et menus examinés. Leur charge et affichage restent gate.
- 47 manifestes entiers lus ; chaque entrée filename existe. Les entrées Touch
  Bar 1x sans filename sont des slots optionnels, pas des ressources manquantes.

Le registre JSON contient des preuves spécifiques par source ou les données
entières de chaque manifeste. Empreintes de la version effectivement relue.

## Défaut et seconde passe

[A2-U01](A2-U01.md) : géométrie différée après mode OFF ; rouge baseline code1 et
vert code0 avec vrais AppKit/layout/main queue, defaults en mémoire. Correction
`MPEditorView.updateContentGeometry` garde l'état courant. Réactivation positive
et changement texte avant OFF exercés. Version finale source entièrement relue.
Root seul stage/commit ; aucune mutation Git effectuée par ce lot.

Candidats réfutés : discovery terminal ne conserve pas de snapshot FS périmé ;
NSToolbarItem.image forward réellement vers l'image du button, vérifié dans un
petit processus AppKit sans préférences ; le remplacement du symlink d'installation
est un contrat de réparation historique, donc aucune règle ownership universelle
inventée pour ce chemin. Les erreurs FS propres sont visibles via alertes.

Seconde passe statique : `@finally` drag cleanup et égalité broadcasts empêchent
les échos, cache tree invalidé avant reconstruction, weak delegate/controller,
stream target indépendant retained et callback main, match file exact avant alias,
clamps windows au lieu de frame negative. Leurs contrôles runtime AppKit/FSEvents
et bundle restent ouverts ; aucun quota de défauts ajouté.

## Contrôles effectués

Contrôles syntaxe/refs sur les 304 chemins (contrôle ≠ lecture manuelle) :
47 JSON parsés, tous filename existants ; 8 XML parsés et chaque destination,
target, firstItem, secondItem résolus ; toutes clés des strings nib présentes
dans XIB correspondant ; signatures %@ des textes NSString formatés/pluriels
cohérentes. Aucun défaut confirmé supplémentaire.

`plutil -lint` accepte les strings non vides ; 13 fichiers totalement vides
produisent `Cannot parse a NULL or zero-length data`. Leur fallback Base est
plausible et volontaire : ce résultat n'est pas déclaré bug sans charge bundle.
Les tables partiellement traduites et clés anglaises ne violent pas une exigence
native universelle inexistante. JJPluralForm a été relu et les trois règles corrigées exercées ;
choix de locale par NSBundle dans le bundle compilé reste requis. Ne pas confondre placeholders concordants avec qualité
linguistique native, ni tables source avec ressources effectivement empaquetées.

## Consommateurs et gates initiales (clôturées ci-dessous)

217 strings entières lues, UTF16/BOM décodés, reprises de toutes troncatures ;
les formes/placeholder/IDs/actions/libellés confrontés aux consommateurs et nibs.
JJPluralForm h/m externes entiers relus : nombre de formes, indices/règles,
NSAssert et format numérique. MPDocument.wordCountTitleForKey:number: lit la règle
locale et transmet directement ces formes. A2-U02 corrige les trois incohérences
confirmées fr/pt-BR/is : règle 2/2/15. Test 126 assertions : rouge 22 échecs puis vert 0.
Les trois tables finales entières relues ; voir [A2-U02](A2-U02.md).

setupEditor final, fontes/tab stops et commandes Tab/Backtab/Newline de MPDocument
relus après correction root lignes vides ec48d63. editorConvertTabs pilote encore
insertSpacesForTab, sélection non vide pilote indent, Backtab unindent ; la création
des tab stops ne dépend pas des ranges de lignes vides. La garde géométrie consulte
le mode courant au moment du callback et conserve frame fallback OFF. Aucun autre
défaut confirmé sur ces interactions. Rendu root 874509a : préférences continuent
à alimenter délégué renderer, les callbacks UI n'effectuent pas de commit HTML propre.
Le label Math support requires Internet connection reste justifié par le CDN
de MPRenderer.mathjaxScripts ; bootstrap/init locaux seuls ne prouvent pas offline.


Gates requises au premier état (désormais exécutées par root et examinées ci-dessous) :
rejeu A2-U01/A2-U02, build catalogue
et resources registration, load nib/bindings, AutoLayout de toutes préférences,
menus/toolbar/Touch Bar actions, document split/sidebar resizing/native tabs,
FSEvents save notifications, font/paste/drop/substitutions et usage des locales
compilées. Aucun Xcode, préférence réelle, opération Finder/clipboard réel,
déploiement ni mutation Git n'a été exécuté dans ce lot.


## Seconde passe finale et décisions de validation — 431c456

Décisions prises manuellement après confrontation des contrats ; aucun passage
`SHA inchangé → validé`. Les SHA identifient seulement les versions examinées.
Les seuls changements depuis les lectures précédentes étaient MPPreferences.h/m :
les deux fichiers finaux ont été entièrement relus ici, APIs pending retirées,
consommateurs Main et tests migrés. Aucun autre SHA du lot n'a changé.
Chaque ligne JSON porte maintenant sa `validation_decision` spécifique.

Root a exécuté et obtenu **1431 XCTest / 0 échec**, **4 XCUITest / 0 échec** sur
build/AuditCampaign02, final 431c456, isolation/restauration CF vérifiée par root.
Logs inspectés : `/tmp/macdown-campaign02-full-tests.log` et
`/tmp/macdown-campaign02-ui-tests.log`. Les quatre UI tests portent seulement sur
launch/window, présence editor/preview et frappe ; ils ne couvrent pas toutes les
branches UI. Les garanties détaillées viennent de lecture + tests natifs ciblés :
préférences42/resizabilité31/terminal19/toolbar63, pasteboard9/substitutions30,
tree11/sidebar23/FSEvents6/drag5/sync11/workspace8/Main commands7,
panes31/zoom26/lifecycle49/export réel/compteurs/sélection. Fontes réelles exercées
par préférences/zoom ; panel delegate/action/font validation également relus.
Les tests de resizabilité (fichier entier relu) chargent les cinq vrais nibs,
contrôlent AutoLayout/fitting/wrapping et exécutent les deux diagram bindings.
La correspondance source des autres bindings/selectors/formatters est issue des
lectures intégrales et contrôles IDs, pas supposée à partir des quatre UI tests.
Root a également rejoué A2-U01 AppKit/mainqueue et A2-U02 formatter126/0.

Bundle Debug effectif inspecté : huit nibs Base présents, Assets.car 981720 octets.
`assetutil --info` donne tous les **43 noms attendus** (les 47 manifests comptent
quatre dossiers/groupes supplémentaires), aucune absence. Tous filenames source
étaient déjà vérifiés après lecture intégrale des entrées. Assets.car contient
également quatre packed assets générés, qui ne sont pas sources supplémentaires.

**217 strings présentes** au bon chemin locale/nom ; **204 tables non vides**
strictement identiques sémantiquement aux sources par plutil JSON, **13 vides**
conservées avec fallback Base, aucune absence ni divergence. Les règles bundle
fr/pt-BR/is sont 2/2/15. Processus Foundation borné, sans app/préférences globales :
`/tmp/macdown-a2-ui-bundle` interroge de vrais NSBundle locale pour chaque table :
**217 tables, 5184 clés non vides, 13 vides, 0 échec** ; compilation60s/runtime30s.
Cela complète le contrat de ressource effectivement consommable, sans déclarer
une qualité linguistique native exhaustive ni un rendu pixel dans toutes langues.

Seconde passe : callbacks geometry OFF/re-enable, watcher stop/dealloc/main,
sidebar equality broadcasts/drag exceptions/links exact, resizabilité text wrap,
font/tabstops et retrait legacy handoff reconsidérés avec leurs consommateurs.
Aucun finding confirmé ouvert du lot ni hypothèse déterminante restante.
**304/304 validés dans ce périmètre ; aucune gate requise restante pour le lot.**
Limites : matériel Touch Bar, clic manuel de chaque bouton/NSFontPanel, rendu de
chaque locale à chaque taille et vérification linguistique native ne sont pas
exercés exhaustivement. Ces limites n'affirment aucune couverture universelle et
ne deviennent pas des exigences nouvelles sans contrat métier correspondant.
Aucun Xcode/Git ni source applicative modifié par cet agent pendant cette clôture.

Rapports horodatés et commandes exactes : [campagne02-ui-bundle.json](campagne02-ui-bundle.json), [assetutil intégral](campagne02-ui-assets.json). Inspection finale SHA : 304 chemins exacts, 0 divergence, après décisions manuelles.
