import json
P='MPGeneralPreferencesViewController::'
M='MainMenu::'
common_keys=[P+'aYQ-0c-EOQ.title',P+'aSv-Bc-cel.title',M+'F0l-dr-Op1.title',M+'aSv-FL-tgl.title',M+'Sd1-br-Tg1.title',M+'TQb-x5-V3x.title',M+'zIn-01-ABC.title',M+'zOt-01-GHI.title',M+'zRs-01-PQR.title',M+'pLw-9G-hNv.title']
T={
'de':["Im Vorschaumodus starten","Dokumente automatisch sichern und neu laden","Ordner öffnen …","Automatisch sichern","Seitenleiste einblenden","Unsichtbare Zeichen einblenden","Vergrößern","Verkleinern","Tatsächliche Größe","MacDown 3000 auf GitHub"],
'es':["Iniciar en modo de previsualización","Guardar y recargar documentos automáticamente","Abrir carpeta…","Guardar automáticamente","Mostrar barra lateral","Mostrar caracteres invisibles","Ampliar","Reducir","Tamaño real","MacDown 3000 en GitHub"],
'nl-NL':["Start in voorbeeldmodus","Bewaar en laad documenten automatisch","Open map…","Bewaar automatisch","Toon zijbalk","Toon onzichtbare tekens","Zoom in","Zoom uit","Werkelijke grootte","MacDown 3000 op GitHub"],
'pt-BR':["Iniciar no modo de visualização","Salvar e recarregar documentos automaticamente","Abrir Pasta…","Salvar Automaticamente","Mostrar Barra Lateral","Mostrar Caracteres Invisíveis","Aumentar Zoom","Diminuir Zoom","Tamanho Real","MacDown 3000 no GitHub"],
'fr':["Démarrer en mode prévisualisation","Sauvegarder et recharger automatiquement les documents","Ouvrir un dossier…","Enregistrement automatique","Afficher la barre latérale","Afficher les caractères invisibles","Zoom avant","Zoom arrière","Taille réelle","MacDown 3000 sur GitHub"],
'it-IT':["Avvia in modalità anteprima","Salva e ricarica automaticamente i documenti","Apri cartella…","Salvataggio automatico","Mostra barra laterale","Mostra caratteri invisibili","Ingrandisci","Riduci","Dimensioni effettive","MacDown 3000 su GitHub"],
}
extra={
'fr':{'MainMenu::aSv-FL-tgl.title':None},
}
out={}
for l,v in T.items():
    out[l]=dict(zip(common_keys,v))
H={f'MPDocument::{k}.title':n for k,n in [('H5W-Wu-gPZ','H1'),('rdq-e7-ugg','H2'),('xRF-se-t13','H3'),('QiC-vC-KbR','H4'),('KTn-mr-UBa','H5'),('r5a-yJ-MY2','H6')]}
out['fr'].update(H)
out['it-IT'].update(H)
out['it-IT'].update({'MPDocument::dPo-OZ-Hdz.title':'Testo','MPMarkdownPreferencesViewController::aSK-nR-xMr.title':'Smartypants','MPTerminalPreferencesViewController::Me9-q2-eWj.title':'●','MPTerminalPreferencesViewController::EJe-0p-X4m.title':'Percorso:','MPTerminalPreferencesViewController::0H2-qZ-OjP.title':'<percorso del binario>','MainMenu::vNY-rz-j42.title':'Cancella menu','MainMenu::g9Y-GM-gdh.title':'Aumenta rientro','MainMenu::Jzs-tR-jkL.title':'Diminuisci rientro'})
for l,d in out.items():
    todo=json.load(open(l+'.todo.json'))['missing']
    need={k for k,v in todo.items() if 'same_as' not in v}
    assert need==set(d),(l,need^set(d))
    json.dump(d,open(l+'.done.json','w'),ensure_ascii=False,indent=1)
    print(l,len(d))
