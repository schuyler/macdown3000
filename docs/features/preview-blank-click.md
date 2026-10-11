# Désélection par clic dans l’espace vide de l’aperçu — 10 octobre 2026

## Cause et correction

Le gestionnaire de pression souris effaçait une sélection existante uniquement si la cible appartenait à un segment de texte mappé vers le Markdown. Un clic sur le fond de page ou sur la marge d’un bloc cachait le panneau, mais conservait la sélection DOM. À la relâche ou au prochain événement de sélection, le panneau retrouvait le même mot sélectionné et se réaffichait.

Le même parcours de clic simple s’applique désormais à la page entière. Les contrôles de la modale, liens, boutons, champs, édition explicite, double/triple-clics et gestes avec modificateurs conservent leurs protections. Les événements natifs ne sont pas annulés : une nouvelle sélection par glissement reste possible. Aucun changement du Markdown n’est effectué par cette désélection.

## Validation

- **9 tests natifs réussis** dans `MPFormattingScopeMenuTests`. Le nouveau test couvre 18 combinaisons : deux thèmes × trois formes de texte × trois cibles hors segment (fond, bloc, zone vide). La sélection et le panneau sont vérifiés après 250 ms, au-delà du délai de mise à jour de 120 ms. La source doit rester identique.
- **3 tests UI réussis ensemble** : double-clic sur « test » dans « Bonjour test », clic physique automatisé dans la zone vide sous la modale, puis vérification après 500 ms de la sélection vide et du panneau fermé. Paragraphes, citations et titres dans `Github2 (dark)`. Les tests existants de clic simple, maintien, glissement, double-clic, gras et annulation ont également réussi.
- Cette correction est ciblée ; elle ne certifie pas une nouvelle relecture exhaustive du script ni une nouvelle exécution de toutes les suites du projet.

Le premier passage UI a échoué avant le geste testé : le chemin du fichier avait été saisi dans l’éditeur au lieu de la boîte d’ouverture. Le helper attend désormais l’éditeur, puis le bouton « Ouvrir », avant de poursuivre la saisie. L’échec initial est conservé dans [ses preuves](../audits/deep-audit/preuves/clic-vide-ui-first.log). Les passages finaux sont consignés dans [le log natif](../audits/deep-audit/preuves/clic-vide-native.log) et [le log UI](../audits/deep-audit/preuves/clic-vide-ui-final.log), avec empreintes des logs complets et chemins XCTest. Les sessions et préférences utilisateur ont été isolées puis leur restauration vérifiée.

Commit de correction : `c0fe8a47`. La compilation Release cible Intel et Apple Silicon ; les tests s’exécutent sur Apple Silicon.
