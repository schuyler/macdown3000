# Conservation des styles multilignes lors des conversions en liste

## Défaut confirmé

Un passage `**première\ndeuxième\ntroisième**` appartient à un seul paragraphe Markdown et reste entièrement gras. Ajouter un préfixe de liste à chaque ligne crée trois contextes de parsing indépendants : les délimiteurs initial et final ne se correspondent plus. Le test de reproduction, exécuté avant correction, confirme la perte du gras et l’apparition des astérisques pour les trois destinations.

## Correction commune à la source et à l’aperçu

La transaction existante identifie le paragraphe, obtient ses styles avec le vrai parseur et ferme/rouvre les styles qui traversent une fin de ligne avant d’ajouter les préfixes. Elle conserve les octets existants, les liens, images et codes en ligne opaques, les fins de ligne et les caractères échappés. Une correspondance source unique est obligatoire ; les différents ordres d’imbrication sont acceptés uniquement si l’empreinte complète du DOM reste identique avant la conversion. Une seconde vérification compare tous les caractères, styles et liens après la conversion ; seule la structure de liste et son espacement syntaxique sont autorisés à changer. Une seule transaction garantit l’annulation exacte et le rétablissement.

La détection du paragraphe tient compte du mode d’emphase intra-mot désactivé : les sondages de frontière peuvent modifier le parsing des délimiteurs. L’expansion complémentaire utilise le Markdown inchangé et la preuve globale demeure obligatoire. Aucun HTML n’est inséré dans le fichier source.

Résultat attendu pour une liste numérotée :

```markdown
1. **sdxerfe**
2. **ezrfvzer**
3. **trzevzer**
4. zvzre
5. rzev ze
6. vzzrefvd
```

## Couverture ajoutée

- Reproduction exacte : trois types de liste, contenu source attendu, styles rendus, annulation/rétablissement.
- 540 conversions : 15 combinaisons non vides de gras/italique/souligné/barré × deux modes d’emphase × trois fins de ligne × trois listes × adaptateurs source/aperçu. La référence est le rendu initial réel, y compris les syntaxes combinées que le parseur affiche littéralement.
- 18 conversions complètes/partielles : sans conteneur, encadré ou menu dépliant ; styles des voisins, lien, code en ligne et caractères échappés préservés.
- Visualiseur natif : thèmes clair/sombre, deux modes d’emphase et trois listes ; sélection et modale conservées, puis ajout du gras à l’intégralité de la sélection mixte.

La couverture est ciblée sur ces contrats et ne constitue pas une nouvelle relecture intégrale du dépôt. Les constructions sans provenance sûre sont refusées avant mutation ; les budgets existants de preuve inline restent appliqués.

## Sélections dans les listes à cocher

Le test du visualiseur couvre aussi une seconde action après conversion. Les espaces situés après les cases à cocher doivent être prouvés dans la source pour restaurer une sélection sur plusieurs éléments. Leur correspondance repose sur le checkbox du DOM, le préfixe Markdown, puis le sondage qui double uniquement cet espace. La comparaison du texte inline exclut uniquement ces espaces syntaxiques, après validation complète du payload ; les caractères des labels restent vérifiés. Une grammaire source commune sert ces deux contrôles.

Les inputs générés sont fermés uniquement dans la copie HTML utilisée par le parseur XML de vérification. Cela évite que la récupération HTML déplace des éléments d’encadrés ou modifie les espaces lorsque le gras sépare un nœud texte. Le document source reste exclusivement Markdown.

## Résultats

**43 méthodes XCTest, zéro échec** : les 28 tests de matrice existants et nouveaux, puis les 15 tests de menu avec un vrai WebView. Les produits paramétrés existants (7 744 compositions, 1 331 conversions de lignes, 1 331 conversions de conteneurs, 7 040 bascules, etc.) demeurent exécutés. Les cas supplémentaires couvrent 573 conversions et 12 actions de gras consécutives dans le visualiseur. Deux thèmes et deux modes d’emphase sont exercés.

- [Reproduction avant correction](../audits/deep-audit/preuves/listes-multilignes-red.log) : défaut confirmé.
- [Validation finale](../audits/deep-audit/preuves/listes-multilignes-final.log) : `TEST SUCCEEDED`, coffre et préférences utilisateur restaurés/vérifiés.
- Les échecs intermédiaires de préparation et de diagnostic sont conservés dans `/tmp/macdown-multiline-list-*.log` ; ils ne sont pas comptés comme des validations.

L’exécution est locale arm64. Les tests ci-dessus couvrent les transactions, le rendu et le menu natif ; la suite UI complète et l’ensemble des autres modules ne sont pas relancés pour cette correction ciblée.
