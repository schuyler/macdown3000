# P3-PRINT — terminer un refus et libérer le slot PDF

Avec une saisie preview devenue périmée, exportPdf réserve le slot/destination puis performAfterRender abandonne silencieusement : ni impression ni callback ni libération du slot. Le document reste incapable d'exporter après récupération de la saisie. Défaut préexistant dans dbc6b23, non créé par les corrections de cette passe.

Rouge réel : Pass3/document-red.log, testPDFExportRefusedPreviewDraftReleasesSlotAndCompletesPrint,7assertions : slot/URLs conservés, callback/document/contextabsents, retrypaspossible. WebView, renderer et draft réels ; seul panneau fichier contrôlé. Source/brouillon conservés et aucune publicationPDF.

Correction : performAfterRender retourne son acceptation ; le parcours print construit sa completion et sur refus appelle le même document:didPrint:NO qui nettoie le slotPDF et notifie le delegate avec son contexte. Aucun second nettoyeur ni nouveau pipeline. Déclarations internes/test migrées.

Vert réel : Pass3/context-print-green.log 22tests0échec2,405s, inclut testrefus/retry/context et classe RenderDeferral entière ; coffre restauré. Document6562/Lifecycle2753/Deferral471 intégralement relus après correction, SHA et registre dans squashed-pass3-document.md. Piste distincte d'erreur réseau pendant rendu propre non confirmée : parseAndRenderNow charge HTMLlocal, sous-ressources ignorées, navigation impossible avant commitment=provisional ; pas de reproduction artificielle retenue. Les scripts déjà exécutés dans le WebView restent une autre frontière de confiance, aucune garantie adversariale inventée.
