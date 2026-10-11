# P3-SETEXT — conserver le voisin après suppression de l’underline

Title\n---\n=== : le probe de titres source balisait aussi le délimiteur --- et détruisait sa fonction syntaxique. Après suppression, les parcours source et preview ne protégeaient pas le premier voisin restant === ; Title redevenait H1. Défaut introduit dans les conversions de la correction ee253cc/source et adf7eed/preview, identifié par cette nouvelle passe, non attribué à la baseline sans preuve.

Rouge réel : Pass3/source-heading-red.log, 1test18assertions, LF/CRLF et deux sélections, source/rendu/undo ; Pass3/document-red.log, testPreviewParagraphSetextConversionPreservesFollowingUnderlineLiteral 2assertions. Correction : garder les délimiteurs intacts pendant le probe et regarder après les underlines effectivement supprimés pour insérer une séparation conservant le voisin et le paragraphe. Aucun nouveau parser/pipeline.

Vert conjoint : Pass3/context-print-green.log, 22tests0échec 2,405s, coffre restauré. Les versions finales Autocomplete et Utility sont intégralement relues ; version finale Document/Lifecycle sera relue après la correction PDF indépendante, avant certification globale. Proves complètes dans squashed-pass3-renderer.md et squashed-pass3-document.md.
