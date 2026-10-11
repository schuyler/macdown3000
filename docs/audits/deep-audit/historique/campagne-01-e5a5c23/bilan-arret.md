# Bilan au point d’arrêt — 7 octobre 2026

Arrêt explicite demandé par l’utilisateur. Tous les agents interrompus ; aucune compilation active. Changements conservés dans le workspace, sans commit, push ni installation issus de cet audit. L’application installée précédemment n’a pas reçu ces nouvelles modifications.

## Couverture certifiée dans le suivi

477 fichiers actifs inventoriés, 118 exclusions individuelles justifiées (plus racines de dépendances installées/générées). 402 fichiers disposent d’une preuve de lecture, 401 d’analyse ; **0 validation finale**. Le SHA peut correspondre à une version antérieure entièrement lue ; les fichiers modifiés requièrent relecture finale. Les cases restantes ne prouvent pas une absence de lecture : certains lots ont été lus, mais leurs preuves finales n’étaient pas encore enregistrées au moment de l’arrêt, notamment rendering/build-tools. Aucune certification extrapolée.

## Corrections présentes, validation finale à terminer

- Rendu : parsing hors thread principal, générations pour écarter les résultats périmés, attente bornée, pipeline partagé application/Quick Look, échappement des attributs de code, erreurs Mermaid traitées comme texte.
- Édition : titres/listes avec sélection bornée, marqueurs numérotés de longueur variable, désindentation, géométrie Unicode, presse-papiers ; cases à cocher associées aux offsets réels du rendu, snapshot/token, édition undoable via le manager du document.
- Document : export attend un rendu frais, callbacks d’impression correctement retenues et arguments correctement transmis, cycle de vie des watchers/fermeture, cache du head et scripts, sauvegarde de contenu avant chargement de fenêtre, erreurs UTF-8/HTML, alignement scroll borné en mémoire.
- Données et fichiers : erreurs/cycles/mutabilité/écriture YAML, capacité UTF-8 JavaScript, overflow du parseur de thèmes, génération du parser, liens symboliques et scope local, fichiers temporaires privés uniques, garde d’ownership du terminal.
- Préférences/UI : migrations sans écritures tardives après timeout, dossiers de sidebar, bindings diagrammes, traductions certaines et inclusion des localisations orphelines.
- Build/CLI/CI : génération commune Prism/styles, échec Sass propagé et sortie atomique, génération de versions, lecture de pipes retardés et noms de fichiers littéraux, restauration des macros de génération même après erreur, statut des tests propagé, smoke-test commun réservé à CI et arguments de release protégés.
- PDF : modèle DOM à occurrences explicites et garde de cardinalité mis en place ; **un nouveau test échoue, correction non validée**.

## Vérifications réellement effectuées

- Dernier lot Xcode large : 376 tests exécutés, 375 réussis, 1 échec dans le nouveau test d’état modifié des cases à cocher. Ce test isolé a ensuite réussi après correction du rattachement de l’undo manager et attente de la notification AppKit. Le lot complet n’a pas été relancé sur l’état final.
- Lot I/O/PDF/cases : 84 tests, 5 assertions en échec dans deux tests ; le test cases est ensuite passé isolément. Le test PDF inline reste en échec.
- Dernier diagnostic PDF : la fixture attend 2 occurrences, PDFKit en renvoie 3 ; aucun correctif supplémentaire effectué après l’arrêt.
- Tests CLI natifs : lecture de pipe retardée, chemins spéciaux, erreur de lecture — réussis.
- Tests synthétiques des outils : 7 scénarios — réussis ; 9 YAML et 52 blocs shell contrôlés, contrats argv/version/générateur/garde CI — réussis.
- JavaScript Mermaid et classification des repères de scroll — réussis.
- Compilations Debug effectuées au fil des tests ; défauts de cycle Xcode trouvés puis corrigés. Build propre local sans CI, Release universelle et suite complète finale — non exécutés.

## Points ouverts au moment de l’arrêt

1. Finaliser le diagnostic du test PDF inline et ses correspondances de texte/geometry.
2. Correction du préprocesseur pour inline code et fences dans les containers Markdown en cours ; arrêter sa certification tant que tests app/Quick Look ne passent pas. Unicité des IDs de titres répétés identifiée comme piste, non encore validée/corrigée.
3. Pluralisation russe/ukrainien/slovaque/tchèque : règles à trois formes, ressources à deux formes ; défaut confirmé, correction linguistique non appliquée.
4. Consolider les preuves manquantes, réconcilier inventaire final et empreintes, relire les derniers deltas, exécuter toutes les suites et builds.

L’audit est **interrompu et incomplet**, et le dépôt **n’est pas certifié prêt à livrer**. Les changements peuvent comporter des régressions non détectées faute de gates finaux. Aucun fichier marqué validé artificiellement.
