# Campagne03 — complément gates CI et inventaire physique

Après lecture intégrale des harness/contrats et de test.yml :

- `stall_empty_suite_tests.py` PASS : fixture temp taskpolicy, aucun vrai Xcode, suite vide NORUN rejetée.
- `Sandbox/preferences_tests.py` PASS : Foundation/CFPreferences et sandbox adhoc réels; suite UUID synthétique seulement, denied puis granted/read-only, écriture refusée, valeur intacte; suppression suite vérifiée par lecture absence.
- macOS conserve les métadonnées protégées des containers UUID `org.macdown.audit.reader.8c8b3faee02b4e8f9e8220a2ded27ad1.denied` et `.granted`. Aucun changement permissions, aucun domaine MacDown réel lu/écrit.
- Sandbox/assets entièrement inspecté (Python + contrat Objective-C), réservé root : écrit uniquement fichiers UUID nouveaux dans les répertoires réels Support app, sans toucher existants. Root a confirmé ce partage.
- Gates précédemment exécutées vertes dans cette campagne (scripts/version/release identity/package/PEG/YAML/queue/staple et JS) non répétées : aucune version des 72 sources build ni 60 render n'a changé depuis les lectures finales. SHA est seulement contrôle identité.
- AppKit/QL/WebKit/UI/Xcode restent exclusivement root. Localization Foundation coordonnée au lot concerné.

Réconciliation `os.walk` incluant fichiers cachés, sans Git/index : 482 baseline, unique source propre additionnelle `Tools/release_asset_checksums.py`, déjà intégralement auditée; aucun symlink inconnu. Racines exclues et caches/utilisateur explicitement séparés. Rapport JSON physique liste exclusions parcourues/élaguées; aucune certification du contenu interne tiers ou données build.

Liste des versions de harness effectivement lues et commandes : campagne03-ci-build-gates.json. Ce complément n'active aucune validation centrale.

Coordination finale root : plural rules126/pluralcounts360 et wordcounter3120 frais PASS, preuves campagne03-ui. Source helper désormais intégré au ledger483, aucune source propre inconnue restante.
