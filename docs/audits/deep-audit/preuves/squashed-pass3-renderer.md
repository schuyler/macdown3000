# Nouvelle lecture indépendante, passe 3 — Renderer et édition source

Révision initiale : `17dbbb9ba39746b4c216278b764b2d95fe1ce801`. Date : 2026-10-09. Cette passe repart de zéro : aucune lecture, analyse ou case de validation héritée des notes précédentes. Code de production/index/Git/Xcode non modifiés par ce lot ; un test RED nouveau autorisé et ajouté pendant cette passe.

## Lecture intégrale actuelle

Lectures non tronquées réalisées : MPRenderer.h 1–84, MPRenderer.m 1–240/241–480/481–720/721–953 ; Autocomplete.h 1–40, Autocomplete.m 1–270/271–540/541–805 ; RenderingTests 1–330/331–660/661–990/991–1310 ; UtilityTests initial 1–380/381–760/761–1137. Après les changements, nouvelle lecture intégrale finale : Autocomplete.m 1–405/406–810 ; UtilityTests 1–400/401–800/801–1178. Aucune sortie tronquée. Les autres quatre fichiers sont inchangés depuis leur nouvelle lecture complète dans cette passe.

| Fichier | Lignes présentes | SHA-256 actuel |
| --- | --- | --- |
| `MacDown/Code/Document/MPRenderer.h` | 84 | `897256ea8bb4616dec80592c49c7e02c82bc1ad42f3a43f7c34cc23f213cba6d` |
| `MacDown/Code/Document/MPRenderer.m` | 953 | `cd6b9a332b52f2a160d9c530d59c1fae3246642fa01679953d8c827cafb418e2` |
| `MacDown/Code/Extension/NSTextView+Autocomplete.h` | 40 | `9412de885b8ff167500177ee83787e485eed5cd4d1ea2de781f4ea3d15ef40e2` |
| `MacDown/Code/Extension/NSTextView+Autocomplete.m` | 810 | `d836b8efb5885b462a142166998b8541e1db51bc22f5eb75796e5817a81c5d6b` |
| `MacDownTests/MPMarkdownRenderingTests.m` | 1310 | `44f669b2b84c7a39c8b606798e90b6feedd0a79a3a31de9a6e24cbf97e1460a1` |
| `MacDownTests/MPUtilityTests.m` | 1178 | `f105769938f2ea657a4f76613a9cfabb725e6f9f7d5819e0d960f6cb29075f70` |

## Parcours et symboles examinés

Renderer : URLs Extensions/Prism minifié et fallback/extras ; MPHTMLFromMarkdown preprocessing/UTF-8/SmartyPants/TOC/callouts/tasks ; MPGetHTML options styles/scripts/template/titre échappé ; égalité nilable ; add_to_languages dépendances et reorder ; language_addition alias/registre immutable ; checkbox_addition ; create/free renderers HTML/TOC ; escape attribut/texte ; CSP/meta token ; checkboxOffsetsForMarkdown options explicites ; init/file série ; getters baseStylesheets/prismStylesheets/prismScripts/mathjaxScripts/mermaidScripts/graphvizScripts/stylesheets/scripts ; readiness/maxDelay/génération/cancellation ; parseNow/Later, invalidations, parseOptions, parseResult, snapshot, publish et parse synchrone ; delegateWraps ; render ressources/timestamp/cache ; export styles/highlighting/diagrammes/mathjax.

Autocomplete : tableaux des paires/quotes Unicode/markup/strike ; substringInRange prefix/suffix/strong-emphasis ; tab par colonne/sentinel IME ; insert simple contre replacement ; completeMatchingCharacter markedText/smart quotes/paires/skip fermeture ; wrapText/wrapMatching ; deleteMatching bornes ; unindentForSpaces colonne/pas de suppression prose ; toggle inline sélection ; toggleBlock marker entier/branches marked/nonmarked/selection ; indent lignes/interiorblank/EOF ; unindent tabs/espaces et mapping ; contenu mappé, map, tempfile et image ; continuation liste vide/bullet/numéro/increment/réutilisation ; quote/réutilisation et indent ; makeHeader préconditions, bornes, lignes LF/CRLF, EOF, probe ATX/Setext dans le contexte complet, preuve HTML, suffixe, suppression de l’underline, paragraphe et échappement, séparation, mapping, no-op et undo.

RenderingTests : setup/teardown/fixtureloader/goldenhelper et branches REGENERATE, parse réel ; golden blocs inline/fenced/langues/listes/tables/tasks/emphase/liens/quotes/rules ; checkboxes indices/casse/imbrication/listes mixtes ; régressions prose/code/références ; nil/vide/whitespace/malformed/10000 lignes ; CRLF ; slugs UTF-8/entités/collisions/TOC/scope emoji/cyrillique/grec ; titres vides ; action de soulignement source et préférences restaurées ; callouts et code littéral ; snapshot isolation/options changées/export vivant.

UtilityTests : setup/cleanup ; thèmes/styles/dédoublonnage/extension/fallback/pruning/hash ; JavaScript/sérialisation/Unicode ; clipping/pasteboard/fichiers/traversée de chemin temporaire ; édition, sélection, indentation, marqueurs et undo natif ; conversion des titres sourceSetext/ATX/LFCRLF/littéraux/contexte/1000 lignes ; YAML aliases/récursion/streams/mutabilité/clefs composées ; capacité du parser de styles ; paste URL ; géométrie Unicode. Le composant garant des nouveaux tests source est NSTextView + MPRenderer/Hoedown réel.

## Dépendances relues pendant cette passe

Lecture entière nouvelle : MPRendererTestHelpers.h/.m, template default.handlebars, MPMarkdownPreprocessor.h 1–180/181–329, MPAsset.m, hoedown_html_patch.h/.c 1–220/221–440/441–616, MPQuick LookRenderer.m 1–185/186–376. Hoedown document.c sections is_atxheader/is_headerline/is_next_headerline/parse_paragraph/parse_atxheader. MPDocument consumers publication/resources/bodyreplacement 2543–2660, prefs invalidation 2890–2940, export différé 3260–3296, sept appels H1–H6/paragraph 3446–3495 ; snapshots mapping 5410–5605, block 5810–5965, inline 6038–6066. MPDocument lecture entière est confiée au lot Document ; les plages ici établissent les consommateurs nécessaires du renderer.

## Invariants réexaminés et vraie seconde passe

1. Snapshot ne publie ni HTML, langues, source/offset/token checkbox ni génération/queue. Résultat et contextes locaux pour chaque parse. Les alias/langue maps dispatch_once restent immuables ; tokens UTF-8 et contextes C ont une durée de vie précise couvrant callbacks synchrones. Sync/liveasync partagent parseResult ; flags et options viennent du même delegate.
2. Async : source/options capturées sur main, cancellation avant/après parse, génération vérifiée avant publication et readiness. Les probes main synchrones ne suppriment pas la parse en attente. Le consommateur empêche publication Web pendant draft et filtre fermeture. Aucun accès concurrent au delegate ajouté par ce snapshot ; consommateurs applicatifs sur main.
3. Cache ressources : styles/scripts sont produits d'après languages publiées ; changements head/script déclenchent reload consommateurDocument. Checkbox token ignoré pour signature mais mise à jour DOM explicite. CSP devant Markdown dans head ; Quick Look a politique scripts/réseau volontairement différente et utilise le même preprocessing/patch C.
4. Sourceheading : oracle doit préserver syntaxe des candidats voisins et conversion doit rester paragraphe après suppressionSetext. Relecture des combinaisons LF/CRLF, prose avant titre, HTML brut/code, hashes terminaux suivis d’espaces, contenu de titre -/#/numéro, voisin thématique, sélection des marqueurs et Unicode. Les preuves regex sont locales auHTML rendu et ne remplacent pas le parser.
5. Undo/mapping : remplacement natif unique ; pas d'écriture si refus avantcommit ; bornes sélection UTF-16 et lignes physiques. Les tests n'affirment pas le timing exact, mais source/rendu/sélection réels et mesure 1000 lignes.

## Candidats et conclusions actuelles

Aucun nouveau défaut confirmé dans MPRenderer. Candidats écartés par chaîne actuelle : nil/front matter normalisé par preprocessing ; durée C token/contexte couverte ; Prism snapshot registry non publié ; invalidation des flags prise en charge dans Document ; template singleton correspond au template applicatif fixé par préférences initiales (pas de flux UI de changement identifié dans le périmètre).

**Contexte Setext consécutif ouvert, confirmation statique nouvelle** : source `Title\n---\n===\n`. Sélection de Title seulement : underline --- supprimé mais === restant devient nouveauH1 de Title. Sélection de Title+--- : probe groupé marque aussi --- (candidat devant ===), change son statut d’underline et retire la preuve que Title est H2. Chaîne complète Hoedown : is_headerline/parse_paragraph ; précondition atteignable par bouton Texte normal. Nouveau test réel `testNormalTextSetextConversionPreservesConsecutiveUnderlineContext`, LF/CRLF, deux sélections, source, rendu du voisin, undo et redo, ajouté sur autorisation du parent. RED natif en attente, aucun correctif production encore appliqué. Cette preuve rouvre la validation Autocomplete et parcoursconsommateurs concernés.

Les suites de la campagne précédente ne sont pas une preuve d'exécution de ce nouveau test. Aucun verdict prêt à livrer délivré pendant cette passe ; parent centralise gates et commits et clôture.

## Confirmation native, correction et relecture finale

Le parent a exécuté le test source RED dans le coffre isolé : `build/SquashedPreviewAudit/Pass3/source-heading-red.log`, xcresult 01-25-02, sortie65, 1 test, 18 assertions en échec. Les préconditions de rendu initial ont passé : il s'agit réellement de H2 Title puis du titre H1 vide voisin. Le défaut de conversion est donc confirmé par le composant réel, et pas seulement par la chaîne statique. La variante preview est prise en charge dans le lot Document pour la même cause.

Correction source minimale autorisée après RED : les lignes qui sont elles-mêmes des délimiteurs Setext ne reçoivent plus un marqueur de candidat-title dans le probe batch, ce qui conserve le statut syntaxique de l'underline du titre précédent. Le voisin à protéger après conversion est désormais le premier voisin qui reste après suppression effective de l'underline, et non simplement la ligne i+1 de la source initiale. L'insertion d'une séparation vide conserve le texte converti en paragraphe et le titre vide voisin à son propre emplacement. Une seule parse du document complet ; même parser/options ; mapping et undo natifs inchangés.

La totalité des 810 lignes du helper et des 1178 lignes des tests a été relue après ces changements (plages ci-dessus). Seconde passe : aucune mutation du délimiteur de voisin dans le probe ; candidats sans chevauchement ; skipper uniquement les underlines que l'oracle a réellement identifiés et qui sont retirés ; séparation LF/CRLF identique au titre ; sélection Title seul ou incluant underline ; conservation du voisin hors sélection ; code/rawHTML/fences toujours soumis à la preuve complète et à la preuve locale avant mutation. Aucun autre défaut confirmé dans ce lot à ce stade. Test GREEN conjoint source/preview et suites finales en attente ; cette note ne coche pas la validation de livraison avant leurs résultats.

## Gate ciblé de cette passe

`build/SquashedPreviewAudit/Pass3/context-print-green.log` : le test source `testNormalTextSetextConversionPreservesConsecutiveUnderlineContext` passe, lignes 4029–4032, 1 test / 0 échec / 0,005 s. La campagne ciblée conjointe termine avec 22 tests / 0 échec, 2,405 s (lignes 4034–4036) et restauration vérifiée des préférences (4047). Le défaut source est corrigé et vérifié par son test natif sur les empreintes finales indiquées. Les suites de livraison complètes restent centralisées par le parent : ce gate ciblé ne les remplace pas.

## Clôture centralisée de cette nouvelle passe

Les états intermédiaires ci-dessus sont historiques. Vérifications finales terminées :1476 XCTest complets Intel/Rosetta,13 XCUITest ARM,65 contrats CLI, syntaxe JS, Release universel et signature locale, tous réussis. Test HTML final Intel/ARM après renforcement completion réussi ; aucune modification applicative postérieure aux preuves. Sources finales rapprochées des SHA relus ; tous fichiers modifiés intégralement relus après leur dernière correction et secondes passes terminées. [Clôture et limites](squashed-pass3-cloture.md), [preuves et versions exactes](squashed-pass3-verification.json).
