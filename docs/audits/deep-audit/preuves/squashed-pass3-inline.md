# Passe 3 indépendante — transaction inline, compteur et contrats

Baseline17dbbb9. Toutes les lectures ci-dessous refaites dans cette nouvelle passe, sorties entières sans troncature. Pas de validation héritée.

| Fichier | Plages neuves | SHA-256 |
| --- | --- | --- |
| `MacDown/Code/Document/MPPreviewInlineTransaction.h` | 1–559 | `618db0c670ad51b85755258eb1cc27dfdc49f8facd64f060be05cca31434c039` |
| `MacDown/Code/Extension/DOMNode+Text.h` | 1–33 | `748eb6ded390d9261d7454819f8e2486b65735ff7f2239495208cb05952daed3` |
| `MacDown/Code/Extension/DOMNode+Text.m` | 1–164 | `1595fa2638565bbf1af3d46d22ebc7d47cec468a55c7802d715b8877550d3218` |
| `MacDownTests/MPSelectionCountTests.m` | 1–275 | `8b837d4a99ffefd61ccb535fa045edf975109e9c5e76ac7fafa493794c8e0293` |
| `MacDownTests/BuildTools/inline_transactions_tests.m` | 1–125 | `0c9b795a7550a62d56fe5f89816d7691f7be4f93d0c9bdcb662f60d5945a0938` |
| `MacDownTests/BuildTools/inline_transactions_tests.py` | 1–13 | `49fd9a1b05cdc9cf5954dcf43754316e326eed26e384d4fa509405d51d530e39` |

## Registre et analyse de toutes les fonctions

MPPICollect : chaque kind, tags/styles reconnus, strict whitelist, récursion ; MPPIParseHTML : XML puis tidy, nil et entitiesnever ; InlineOracle : un seul p/bodychild, styles par UTF16, trailingNL ; Provenance : états countcap2, syntaxescape, path100k/states1024/length20k, résultatunique/reconstruction ; Marker : chaque masque/spelling ; Serialize : ownership liens/outsidecommon, stackprefix/delimiters/codefence, run whitespacecache, surrogatepairs/stylesidentiques, endpoints ; FingerprintNode : ancestorlink attrs, chars/masks/newlineartifacts, tagsstyle vsstructure, legacyspanstyles, children ; Fingerprint : bodyrequired ; palette9wrappersimmutableonce ; WithoutLegacyTags : positions et whitelist ; MaskOpaque : regexatoms, ownershipcolorrequired, explicitclearfullonly, lienssplit, UUIDabsence et restaurationpositions ; SingleChange : action/url/bornes, lineprefix/LFCRLF/bodylimit, atomproxy/oracle/provenance, linkvisible et selectedbounds, togglecommon/clear/link, variantesorder/spelling, reparseexpectedstyles, atoms inverses, full-documentfingerprint et retainedselection ; Change : paragraphe softwrap puis decomposition lignes,128items, modecommun, deltas non contradictoires, fingerprintfinal, inverse replacement et selectionmultiline. Toutes les branches de refus ont été relues dans leur chaîne native (lot Document suit ses consommateurs). Aucun nouveau défaut confirmé dans ce helper.

DOM compteur : Make/Zero/Add/String etnil/vide, dispatchonceICU/UTF16/newlines ; Children agrégés ; Node switchtypes, tokenheadownedui, excludescript/style/head/precode, inlinecodeoneword ; wrapperpublic etcategoryidentique. Nouvelle hypothèse mots intra-mot : somme partextnode ignore continuationinline ; les métadonnées ne divisent pas nœuds, hypothèse metadata seule réfutée. Styleinline répartit un mot dans plusieursnœuds : reproduction WebView et correction coordonnées au lotJS avantvalidation.

Tests entièrement relus : Countingnil/empty/whitespace/characters, préférencesrestore et coordinationaffichage, vraiWebViewhidden/visible/authoredcounts. Runner CLI entièrement relu : clang temporaire + vraiHoedown/timeout, mémoire C freed ; 65contrats actuels incluantUTF16/CRLF/liens/code/legacypalette/nestedrefus/whitespace12k/limits. Deux assertions sourcenatives supplémentaires (punctuation/mixedcode) incluses sans comptage inflationniste. Nouvelle exécution centralisée dans Pass3/inline.log, résultat à consigner.

## Seconde passe indépendante

Réexamen sourceunique vs liveDOM, sourcebounds et surrogate, provenanceambigue, stylewhitespace, opaquelegacyhorssélection, lienssuperposés et URL, refus sansmutation, ordre de deltas et constraints20k/128, coût whitespace linéaire. Aucun nouveau bug confirmé du helper ; compteur en cours de reproduction. Les commentaires du code fondent le contrat UTF16 et inlinecode1, ils ne justifient pas des mots artificiels aux frontières bold/em.

Auxiliaires relus de nouveau : Podfile complet, workflow test.yml et deux schémas XCTest/UI ; coffre Python entier et helperCFPreferences entier, refus appconcurrente, exacteidentitéduhost, sauvegarde/récupération/restauration vérifiée, namespaces et snapshots privés. Guides 47/120 lignes et JSON237 lus en entier, capture PNG inspectée ; documents de feature clairement historiques, aucune ancienne suite utilisée comme validation nouvelle.

## Résultats et relecture finale du compteur

Le candidat compteur a été confirmé dans un WebView réel, puis corrigé dans `55629e7` ; voir [preuve dédiée](squashed-pass3-count-fix.md). Root a relu la version finale complète DOMNode+Text.m1–201, SHA `012b469069e5ba220c530ae1de0df9811585ceca7628330da984723139b56b8d` ; le lot JS a également relu entièrement cette version et les275 lignes de MPSelectionCountTests.m. Le tableau initial DOM164 décrit la lecture avant correction et ne certifie pas la version finale. Tampon inline, flush aux frontières de blocs/BR, métriques caractères, CODE atomique et PRE exclu réexaminés. Plus de candidat déterminant ouvert.

Exécution nouvelle `build/SquashedPreviewAudit/Pass3/inline.log` : 65 contrats réussis, sortie0 ; syntaxe preview-edit.js vérifiée par node --check, sortie0. Suite native complète :1475 tests, zéro échec, restauration vérifiée. Voir clôture pour les gates finales après tests UI/build.

## Clôture centralisée de cette nouvelle passe

Les états intermédiaires ci-dessus sont historiques. Vérifications finales terminées :1476 XCTest complets Intel/Rosetta,13 XCUITest ARM,65 contrats CLI, syntaxe JS, Release universel et signature locale, tous réussis. Test HTML final Intel/ARM après renforcement completion réussi ; aucune modification applicative postérieure aux preuves. Sources finales rapprochées des SHA relus ; tous fichiers modifiés intégralement relus après leur dernière correction et secondes passes terminées. [Clôture et limites](squashed-pass3-cloture.md), [preuves et versions exactes](squashed-pass3-verification.json).
