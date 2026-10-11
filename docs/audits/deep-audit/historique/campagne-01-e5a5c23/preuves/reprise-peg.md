# Reprise PEG et highlighter — 2026-10-07

Preuve complémentaire. Les 21 sources ci-dessous ont été entièrement relues et analysées ; chaque empreinte représente le contenu relu après correction RP01. Le suivi principal et les anciennes preuves sont conservés. `Validé` global reste vide : Cocoa/Xcode et AddressSanitizer sont des gates distinctes.

## Correction nouvelle confirmée

**RP01 — taille des objets AST du générateur.** `_newNode` allouait `sizeof(struct T)` puis utilisait une adresse typée `union Node`, plus grande. Strict UBSAN a interrompu la génération réelle de la grammaire avec `insufficient space for an object of type Node` dans makeName. Allocation de `sizeof(Node)` unique corrigée ; même parcours strict UBSAN vert. Aucun changement de sémantique de grammaire. Commit autonome requis, distinct des changements hérités EU16 du même tree.c. Version héritée sans RP01 sauvegardée `/tmp/macdown-tree-eu16-before-rp01.c` pour séparation du commit.

## Contrôles et limites

- `python3 MacDownTests/BuildTools/peg_contracts.py` : exit0 après correction, UBSAN `halt_on_error=1:print_stacktrace=1`. Copie isolée, vrai make/clang/greg, génération parser final puis compilation/exécution C public. Cas vide/header/strong/quote/list/ref/Unicode/notes/math, tri et free ; URL explicite et référence résolue réellement consommées ; 1000 règles H1 répétées et valeurs vides consommées/libérées ; noms1023/1024/1025/2048, profondeur1100 ; parser généré200 variables exécuté et résultat2 vérifié. Chaque subprocess borné30s (build120s) ; groupe tué sur timeout.
- EU17 : vrai Makefile exécuté dans copie isolée avec core sans marqueur puis deux marqueurs ; exit nonzero dans les deux cas, ancien `pmh_parser.c` inchangé. Pas de génération modifiant la copie partagée.
- `plutil -lint Dependency/peg-markdown-highlight/peg-markdown-highlight.xcodeproj/project.pbxproj` : exit0 ; `sh -n .../tools/combine_parser_files.sh` : exit0.
- ASAN+UBSAN a été tenté. Le bootstrap greg se bloque avant main dans le runtime ASAN Appleclang17/macOS26.6.2. Échantillon `/tmp/macdown-peg-generator-sample.txt` : `AsanInitInternal -> InitializeShadowMemory -> MemoryRangeIsAvailable -> get_dyld_hdr -> dyld_shared_cache_iterate_text_swift -> malloc -> AsanInitFromRtl -> StaticSpinMutex::LockSlow`. Groupe détenu arrêté. Aucun succès ASAN revendiqué et aucune conclusion de défaut PEG tirée de ce blocage environnemental. Relance disponible avec `PEG_SANITIZERS=address,undefined` sur runtime opérationnel.
- Premier run UBSAN permissif invalidé comme preuve de succès : diagnostics stderr pouvaient être cachés sans halt_on_error. Seul run strict après RP01 fait foi.
- Consommateurs pertinents MPDocument (initialisation highlighter et setupEditor), portion HGMarkdownHighlighterTests545–650 relus. Aucun statut lecture intégrale attribué à ces deux fichiers. Inversion flag footnotes dans MPDocument signalée au responsable comme défaut ouvert hors propriété.
- Aucun Xcode, stage ou commit exécuté par cet agent. Gates Cocoa/génération périmée/détachement target restent au responsable principal ; la phase rouge historique EU14–17 n’a pas été recréée.

## Sources relues intégralement

| Chemin | SHA-256 | Lu | Analysé | Validé | Preuve spécifique |
| --- | --- | --- | --- | --- | --- |
| `Dependency/peg-markdown-highlight/HGMarkdownHighlighter.h` | bcaea22152ff4eafffc225792ad8078d006080aef5e457363ccca397d4acf846 | ☑ | ☑ | ☐ | Contrats activation/cibles/styles/extensions/timing/delegate ; types et ownership cohérents avec implémentation et MPDocument. |
| `Dependency/peg-markdown-highlight/HGMarkdownHighlighter.m` | f7d378231b6ea3d0e8b514b73ff76b3080a0ea48c1630baddd4c9871bc207498 | ☑ | ☑ | ☐ | 761 lignes : init/dealloc, cible/activation, delegate, attributs/fonts/liens, scrolling/ranges, callback parsing/publication, debounce, styles et réactivation. EU14 capture main puis worker, generation token/cancel évitent publication périmée ; gate Cocoa root. |
| `Dependency/peg-markdown-highlight/HGMarkdownHighlightingStyle.h` | bbcf8aa4a4c0b1fbd0a2f4d8ac7f5d5970eed549b4421816348ccda31b68489c | ☑ | ☑ | ☐ | 99 lignes : attributs, poids/style/underline, couleur/famille et construction public API. |
| `Dependency/peg-markdown-highlight/HGMarkdownHighlightingStyle.m` | f1fe70f79eeebbf45a76a8a8a0605a554c0c40de24b9475860418a7fb025543d | ☑ | ☑ | ☐ | 106 lignes : factory/init/copy, application des traits NSFont, attributs couleurs/texte et plages ; contraste settings/texte relu. |
| `Dependency/peg-markdown-highlight/Makefile` | ba92d8bc7ce58440820495e8f6e5924ae74dfeea50d764f8e931c3c8ff15a7e0 | ☑ | ☑ | ☐ | EU17 dépendances source/headers/generator, recursive MAKE, alias build/install, génération finale atomique. Build instrumenté réel ; marker missing/duplicate échoue et ancien final intact via ce Makefile. |
| `Dependency/peg-markdown-highlight/greg/Makefile` | ed0ae1de93498cdddb251880b6c4426331d2d41e26dd3b8e13341747bc45ae60 | ☑ | ☑ | ☐ | Compilation bootstrap/compile/tree avec dépendance greg.h, CC/OFLAGS/XFLAGS propagation, clean/spotless et régénération ; véritable make strict UBSAN réussi. |
| `Dependency/peg-markdown-highlight/greg/greg.h` | bcdd2c5dc463d8656b563c4e084172a9eb866866a9e33421f2867a4441716dff | ☑ | ☑ | ☐ | 112 lignes : union Node complète, structs de chaque type, API constructors/stack/compile ; RP01 allocation taille union validée strict UBSAN. |
| `Dependency/peg-markdown-highlight/greg/tree.c` | 43854b78d4ae1c28cb51c19d6accf9fac3f4a55ed337b11243d5738fee425311 | ☑ | ☑ | ☐ | 363 lignes : tous constructeurs/listes/visiteurs, makeAction nom dynamique EU16, stack dynamique EU16, allocation union RP01. 2048 identifiant/1100 profondeur réellement générés strict UBSAN. |
| `Dependency/peg-markdown-highlight/greg/compile.c` | 5881904b59c46754dafd020940b978d3d25e7735b68e72435d05383efb752c58 | ☑ | ☑ | ☐ | 755 lignes : emit/escape/options/variables/actions/rules/Node_compile et runtime templates ; EU16 yyPush croît vals et pointeur rebasé. Parser 200 variables compilé et résultat public consommé. |
| `Dependency/peg-markdown-highlight/greg/greg.g` | 41f4a5493cfe1371dc4bfd031daf3d99768b6c9baff2cd2c74dbf3d0e91672f7 | ☑ | ☑ | ☐ | 298 lignes : toutes règles bootstrap/actions/consommation trailers/args/génération ; cohérence bootstrap généré et templates recherchée, nouveau parser exécutable produit. |
| `Dependency/peg-markdown-highlight/greg/greg.c` | c673fb8467fc8bafeca54eb864931f0cef3e5232a0647b9e0a997190453ab157 | ☑ | ☑ | ☐ | 1153 lignes (1–400/401–800/801–1153) : bootstrap commité actif lu intégralement ; yyText réserve terminator EU16, yyPush croissance EU16 et free buffers ; fonctions parsing/runtime/main analysées strict UBSAN. |
| `Dependency/peg-markdown-highlight/pmh_definitions.h` | 3bb4ae80d27facdfcd21b3b68a47855ed063bcfd61dacc2a3ff7f820757867d7 | ☑ | ☑ | ☐ | 124 lignes : types et cardinalités/lang style groups, flags extension public et éléments linked list ; styles array limité examiné EU15. |
| `Dependency/peg-markdown-highlight/pmh_parser.h` | 36724d84cf356938f6c95c75369bd39e97c895f247505d03748072e6135429a3 | ☑ | ☑ | ☐ | 89 lignes : ownership parse/free/sort, positions/adresses et extensions public ; harness consomme réellement chaque liste triée et URL. |
| `Dependency/peg-markdown-highlight/pmh_styleparser.h` | abb30561fb61b29249381eded0b63b604440f45972b8593571710d2aa4956a07 | ☑ | ☑ | ☐ | 147 lignes : enums/styles/value union/API et ownership ; répétitions groupes intégrées à slots fixes EU15. |
| `Dependency/peg-markdown-highlight/pmh_styleparser.c` | ffc1ffd453acc9b2fda193dddc9d3105afe49c16f0c9c9b17b9ea755807e21dc | ☑ | ☑ | ☐ | 947 lignes (1–220/221–620/621–947) : trim/comment/token/rule/attribut/value/error callback/collections/free ; EU15 empty safe et duplicate rule merges. 1000 H1/2000 attrs consommés et libérés strict UBSAN. |
| `Dependency/peg-markdown-highlight/pmh_parser_head.c` | a91476dcaad26de8b1c83bef38925ba30ac80404866f63ec5f107e5b6a77212a | ☑ | ☑ | ☐ | 990 lignes (1–350/351–700/701–990) : allocations buffers/éléments, UTF8, raw-list/references, adressage/ranges/traversals/free et parsing interne ; API réel vide/listes/références/Unicode/extensions testé. |
| `Dependency/peg-markdown-highlight/pmh_parser_foot.c` | 1204e603df3d421acfa8488f0aacb0db8a026c3a415bdf265b626d98101d62cd | ☑ | ☑ | ☐ | 43 lignes : façade parse/sort/free et extensions, appels parser/private cleanup ; public harness strict UBSAN. |
| `Dependency/peg-markdown-highlight/pmh_grammar.leg` | 7295f542e85a37baeffe837fca82cf35b782bd0fb7bccffa072d931c3b5dd50d | ☑ | ☑ | ☐ | 688 lignes (1–350/351–688) : règles blocs/inlines/HTML/notes/math/listes/emphasis/link/ref/UTF8 et actions ; résultat public titres/strong/URL références consommé. |
| `Dependency/peg-markdown-highlight/peg-markdown-highlight.xcodeproj/project.pbxproj` | 298977daa58b795a512e110bed16c65468be7caa66012b8ddc8c36e9796c1a09 | ☑ | ☑ | ☐ | 170 lignes : source mapping/configuration/project dependencies, target make et ACTION build/install cohérents ; plutil réussi ; Xcode root. |
| `Dependency/peg-markdown-highlight/peg-markdown-highlight.xcodeproj/project.xcworkspace/contents.xcworkspacedata` | 14212f4d2947a8a5d9d8ddba30163bada5bd98bfe8eca44fffb0b1da18b53d1c | ☑ | ☑ | ☐ | XML workspace root self ; chemin cohérent. |
| `Dependency/peg-markdown-highlight/tools/combine_parser_files.sh` | c64a2e5286b37481d2449712c1cb24a97e377562bb481467f99467f34d5ad872 | ☑ | ☑ | ☐ | EU17 marqueur unique obligatoire, concaténation header/core/footer ; missing/duplicate fail-fast réel et parser précédent préservé. |

## Tests nouveaux relus entièrement

- `MacDownTests/BuildTools/peg_contracts.c` : SHA-256 `4cd77f0f763c475f8af9d4997464744a31689b64948996ad850dad04ff27923a` ; lu/analyse intégrale, exécution stricte ci-dessus. Assertions consommant API/valeurs et isolation/timeout revus.
- `MacDownTests/BuildTools/peg_contracts.py` : SHA-256 `334f7333069937caf69acf4ec1ef0ba5a95b3b0dbefacf5fca13ee5ce4b5cc0e` ; lu/analyse intégrale, exécution stricte ci-dessus. Assertions consommant API/valeurs et isolation/timeout revus.

## Séparation des commits

- EU14 : HGMarkdownHighlighter.m avec tests Cocoa appartenant au responsable.
- EU15 : pmh_styleparser.c (trim vide et fusion règles récurrentes de même collection ; cause commune de sûreté du parseur de styles), cas dédiés actuels HGMarkdownHighlighterTests et harness public portable.
- EU16 : greg/compile.c, greg/greg.c et tree.c sauf premier hunk `_newNode` ; noms longs, stack AST et vals runtime (séparer causes si exigé par suivi principal).
- EU17 : Makefile, greg/Makefile, tools/combine_parser_files.sh : dépendances/alias/atomic/fail-fast construction et intégration setup.
- RP01 : seul premier hunk tree.c `_newNode` plus peg_contracts.c/py, autonome. Aucun fichier source n’a changé après démarrage du run strict final.
