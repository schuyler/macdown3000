# P3-COUNT — mots indépendants des fragments inline

Compteur ancien : hel<strong>lo</strong> world=3mots ; he<em>ll</em>o world=4, alors que hello world=2. Chaîne atteignable par formatage intra-mot → renderer → DOM → count widget. Défaut préexistant avant dbc6b23 ; les spans de mapping seuls ne divisent pas les textnodes et ne sont pas sa cause.

Rouge réel WebView : Pass3/count-red.log, 1test5assertions, caractères et codes voisins corrects. Correction : tampon de texte inline partagé, segmentation Foundation aux frontières blocs/BR et CODE atomique avec contrat1 ; exclusions nonce/UI/script/style/head/precode conservées. Helpers de caractères UTF16 et API string conservent leurs contrats. Aucune nouvelle grammaire Markdown.

Vert : Pass3/count-green.log, classe SelectionCount entière et test intra-mot du document, 15tests0échec 2,130s, coffre restauré. Dix cas : plain, strong, em, link, span, nested, P, BR, LI, CODE/PRE ; les trois métriques sont vérifiées. DOM201 et tests275 intégralement relus après patch (agent et root ont lu le DOM final) ; seconde passe des exclusions/blocs/Unicode/code dans squashed-pass3-js.md. Suites globales requises avant certification finale.
