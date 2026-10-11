# Campagne03 — lecture root/document

Les 47 fichiers de ce lot ont été relus intégralement dans cette campagne. La lecture de MPDocument.m couvre les 5392 lignes en plages contiguës ; MPMainController.m les 509 lignes. Les contrats consommateurs ont été croisés avec les lots UI/build/rendering fraîchement relus ; les 47 analyses sont tracées individuellement dans le JSON. Validation finale des 47 fichiers prononcée après les gates fraîches documentées dans campagne03-cloture.md.

## Parcours examinés

- Document : initialisation/nib, KVO/notifications, édition et undo, sauvegardes, rendu DOM/rechargement, génération MathJax, défilement, presse-papiers, HTML/PDF, fermeture, clics de liens et cases, watchers et rechargements externes.
- Application : démarrage/Sparkle, migration des anciennes commandes et queue commune, dossier workspace, fichiers d’aide, événements URL.
- Utilitaires/extensions : limites et sélections, autocomplétion, échappement des tables, ressources/cache, sécurité des chemins et exécutables, subprocess Homebrew, archives embarquées, styles/pruning.

## Ressources cachées réellement examinées

`data.map` contient une unique association MoskyかわいいよMosky → PNG de 1500 × 1500, inséré par insertMappedContent quand le texte court correspond. L’image a été extraite dans build/AuditCampaign03/maps/data-image.png et visualisée. Tous les chunks ont leur CRC vérifié ; 177 IDAT, profil ICC Generic RGB (11 tags), métadonnées XMP Pixelmator lus. Aucun programme exécutable n’est présent dans ces payloads.

`treats.map` : graphe NSKeyedArchive de 16 objets décodé, nom mosky, trois payloads Markdown complets pour 0214/0819/0314, CSS centré et pseudo-code Python affiché dans une clôture, un lien Twitter dans le premier ; entrée .DS_Store inactive (6148 octets de métadonnées, aucun jour correspondant). treat() ouvre ces messages si le nom utilisateur commence par mosky aux dates correspondantes. Ce comportement caché est identifié ; pas de suppression spéculative d’un parcours encore accessible.

## Défauts confirmés et vérifiés

- D03-01 : stdout attendu après exit bloque enfant dès remplissage pipe. Fixture avant correctif : timeout1MiB ; drain concurrent après : 1048576octets, callback main. 4XCTest natifs passent ; commit4d9966c.
- D03-02 : paires/espaces/fin de liste vide ignorent refus du délégué et ne notifient pas la suppression. Six variantes allow/veto échouent sur baseline895d6c9 ; correction trois insertText : 12contrats réels AppKit verts, texte/sélection/undo/notifications. Commit1122e1d.
- Rendu/export : cinq contrats Hoedown/WebKit/CSS passent, PDFconsumer12 contrôles avec impressions réelles/réouverture disque/destination/RGBA1294016octets/restauration DOM/CSSOM passent. Différences fastDOM/reload et app/QL ont leurs garde-fous/base et variations légitimes, pas de doublon métier incohérent confirmé.

Aucun ancien résultat de campagne02 ne certifie cette campagne. Suite native fraîche1437/1437 passe sans échec, préférences restaurées/vérifiées. Logs build/AuditCampaign03/{native-all,autocomplete-final-red,autocomplete-final-green,homebrew-xctest,pdf-consumer}.log. Suites FINAL1437+UI4, Debug/Release universels, vrais bundles et Quick Look système terminés ; limites locales dans clôture.
