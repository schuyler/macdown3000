/* Preview editing is a source-range transaction, never an HTML-to-Markdown conversion. */
(function () {
  'use strict';
  var config = window.__macdownPreviewEditConfig;
  var previousEditor = window.macdownPreviewEditor;
  var retainedUI = config && config.selection && previousEditor && typeof previousEditor.elements==='function' ? previousEditor.elements() : null;
  var retainedPanel = retainedUI ? retainedUI.panel : null;
  if (previousEditor && typeof previousEditor.destroy==='function') previousEditor.destroy(!!retainedPanel);
  delete window.__macdownPreviewEditConfig;
  if (!config || !config.nodes) return;
  var panel = null, panelStyle = null, errorMessage = null, active = null, saved = null, timer = null, errorSelection = null;
  var mappedSpans = [], panelClass = 'macdown-preview-ui-' + config.token.replace(/[^a-zA-Z0-9_-]/g,''), runClass = panelClass + '-run';
  var handlers = [], rendering = false, selectingWithMouse = false, menuTimer = null, uiZoom = 1;
  var hoverPreview = null;
  var calloutTypes = ['note','tip','warning','important','caution'];
  function listen(target, name, fn) {
    target.addEventListener(name, fn, false);
    handlers.push([target, name, fn]);
  }
  function send(payload) {
    payload.token = config.token;
    window.location.href = 'x-macdown-preview://edit/?payload=' + encodeURIComponent(JSON.stringify(payload));
  }
  function closeMenu() {
    clearTimeout(menuTimer);
    if(!panel) return;
    var menu=panel.querySelector('[role=menu]'), opener=panel.querySelector('[data-mp-format-menu]');
    if(menu) menu.hidden=true;
    if(opener) opener.setAttribute('aria-expanded','false');
    cancelHoverPreview();
  }
  function cancelHoverPreview() {
    if(!hoverPreview) return;
    var previous=hoverPreview; hoverPreview=null;
    previous.nodes.forEach(function(node){node.remove();});
    previous.originals.forEach(function(entry){entry.marker.replaceWith(entry.node);});
    restoreSelection(previous.selection);
    window.scrollTo(previous.scrollX,previous.scrollY);
  }
  function previewFormatting(action,value) {
    cancelHoverPreview();
    var payload=selectionPayload(action,value);
    if(!payload || rendering || typeof config.formattingHTML!=='function') return;
    var html=config.formattingHTML(payload);
    if(typeof html!=='string') return;
    function parseFragment(fragment) {
      // An explicit body keeps parser-generated callout styles in the fragment
      // rather than letting DOMParser relocate leading styles into its head.
      return new DOMParser().parseFromString('<!doctype html><html><head></head><body>'+fragment+'</body></html>','text/html');
    }
    var snapshot=parseFragment(html);
    // Snapshot rendering never executes document scripts a second time.
    snapshot.querySelectorAll('script').forEach(function(script){script.remove();});
    var originals=Array.from(document.body.childNodes).filter(function(node){
      return node!==panel && node!==panelStyle && !(node.nodeType===1 && node.tagName==='SCRIPT');
    });
    if(!originals.length) return;
    var proposed=Array.from(snapshot.body.childNodes);
    // Keep unchanged rendered siblings (diagrams, images, expanded details,
    // highlighted code) alive. Fall back to the full fragment if runtime HTML
    // has changed the top-level structure beyond the parser's correspondence.
    function meaningful(nodes) {
      return nodes.filter(function(node){return node.nodeType===1 || (node.nodeType===3 && /\S/.test(node.nodeValue));});
    }
    var baseline=parseFragment(config.originalHTML || '');
    baseline.querySelectorAll('[data-macdown-callout-token]').forEach(function(node){node.removeAttribute('data-macdown-callout-token');});
    baseline.querySelectorAll('script').forEach(function(node){node.remove();});
    var before=meaningful(Array.from(baseline.body.childNodes)), after=meaningful(proposed), live=meaningful(originals);
    if(before.length===live.length && before.every(function(node,i){return node.nodeType===live[i].nodeType && node.nodeName===live[i].nodeName;})) {
      function same(a,b){return a.nodeType===b.nodeType && (a.nodeType===1 ? a.outerHTML===b.outerHTML : a.nodeValue===b.nodeValue);}
      var first=0, lastBefore=before.length, lastAfter=after.length;
      while(first<lastBefore && first<lastAfter && same(before[first],after[first])) first++;
      while(lastBefore>first && lastAfter>first && same(before[lastBefore-1],after[lastAfter-1])) {lastBefore--;lastAfter--;}
      if(first===lastBefore && first===lastAfter) return;
      // Formatting always replaces a source envelope. If the parser emitted
      // only an insertion, use the full fragment to retain a stable anchor.
      if(lastBefore>first) {originals=live.slice(first,lastBefore);proposed=after.slice(first,lastAfter);}
    }
    hoverPreview={selection:currentSelection() || saved,scrollX:window.scrollX,scrollY:window.scrollY,nodes:[],originals:[]};
    originals.forEach(function(node){
      var marker=document.createComment(''); node.replaceWith(marker);
      hoverPreview.originals.push({node:node,marker:marker});
    });
    proposed.forEach(function(node){
      var imported=document.importNode(node,true);
      document.body.insertBefore(imported,hoverPreview.originals[0].marker);
      hoverPreview.nodes.push(imported);
    });
    window.scrollTo(hoverPreview.scrollX,hoverPreview.scrollY);
    if(config.math && window.MathJax && window.MathJax.Hub) {
      var preview=hoverPreview, hub=window.MathJax.Hub;
      hub.Queue(function(){
        if(hoverPreview===preview) return hub.Typeset(preview.nodes.filter(function(node){return node.nodeType===1;}));
      });
    }
  }
  function hide() { closeMenu(); if (panel) panel.style.display = 'none'; }
  function clearSelection() {
    clearTimeout(timer); saved=null; selectingWithMouse=false;
    window.getSelection().removeAllRanges();
    if(errorMessage){errorMessage.remove();errorMessage=null;}
    errorSelection=null; hide();
  }
  function draft() {
    if (!active || active.textContent === active._mpOriginal) return null;
    return {action:'replace', id:active._mpID, text:active.textContent, token:config.token};
  }
  function finish() {
    if (active) active.removeAttribute('contenteditable');
    active = null;
  }
  function commit() {
    var payload = draft();
    if (payload) send(payload); else finish();
  }
  function mappedSpan(id) {
    return mappedSpans.find(function(span){return span._mpID===id && span.isConnected;});
  }
  function currentSelection() {
    var selection=window.getSelection();
    if(active || !selection || selection.isCollapsed || !selection.rangeCount) return null;
    var range=selection.getRangeAt(0), matches=[], spans=[];
    // WebKit can put heading/word-selection boundaries on elements rather
    // than text nodes. Resolve the intersection without guessing source runs.
    mappedSpans.forEach(function(span){
      if(!span.isConnected) return;
      if(!range.intersectsNode(span)) return;
      var prefix=document.createRange(), start=0, end=span.textContent.length;
      prefix.selectNodeContents(span);
      if(span.contains(range.startContainer)) {
        prefix.setEnd(range.startContainer,range.startOffset); start=prefix.toString().length;
      }
      prefix.selectNodeContents(span);
      if(span.contains(range.endContainer)) {
        prefix.setEnd(range.endContainer,range.endOffset); end=prefix.toString().length;
      }
      if(end>start) {
        matches.push({id:span._mpID,start:start,end:end,text:span.textContent.substring(start,end)});
        spans.push(span);
      }
    });
    var text=range.toString();
    var selectedTable=spans[0] && spans[0].closest('table');
    if(!spans.every(function(span){return span.closest('td,th') && span.closest('table')===selectedTable;})) selectedTable=null;
    if(!matches.length) return null;
    if(matches.map(function(run){return run.text;}).join('')!==text) {
      // HTML inserts whitespace text nodes between blocks. Those separators
      // carry no style, but every visible character must remain source-proven.
      var root=range.commonAncestorContainer;
      if(root.nodeType===3) root=root.parentNode;
      var walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT), node;
      while((node=walker.nextNode())) {
        if(!range.intersectsNode(node)) continue;
        var start=node===range.startContainer?range.startOffset:0;
        var end=node===range.endContainer?range.endOffset:node.nodeValue.length;
        var selectedText=node.nodeValue.substring(start,end);
        if(!selectedText || spans.some(function(span){return span.contains(node);})) continue;
        if(selectedTable && node.parentElement.closest('table')===selectedTable && !/\S/.test(selectedText)) continue;
        if(/\S/.test(selectedText) || !/[\r\n]/.test(selectedText)) return null;
        var before=null, after=null;
        spans.forEach(function(span){
          var position=span.compareDocumentPosition(node);
          if(position&4) before=span;
          else if((position&2) && !after) after=span;
        });
        var beforeBlock=before && before.closest('p,h1,h2,h3,h4,h5,h6,li,pre');
        var afterBlock=after && after.closest('p,h1,h2,h3,h4,h5,h6,li,pre');
        var separatorBlock=node.parentElement.closest('p,h1,h2,h3,h4,h5,h6,li,pre');
        if(!beforeBlock || !afterBlock) return null;
        // A soft break inside prose joins two independently proven source
        // lines. Fenced code and unproven visible characters remain excluded.
        if(separatorBlock) {
          if(separatorBlock.tagName==='PRE' || beforeBlock!==separatorBlock ||
            afterBlock!==separatorBlock) return null;
        } else if(beforeBlock===afterBlock) return null;
      }
    }
    return {id:matches[0].id,start:matches[0].start,end:matches[0].end,
      runs:matches.map(function(run){return {id:run.id,start:run.start,end:run.end};}),text:text};
  }
  function selectionPayload(action, value) {
    var selected=(hoverPreview && hoverPreview.selection) || currentSelection() || ((rendering || panel.contains(document.activeElement)) ? saved : null);
    if(!selected) return null;
    var payload={action:action,id:selected.id,start:selected.start,end:selected.end,token:config.token};
    payload.runs=selected.runs; payload.text=selected.text;
    if(value !== undefined && value !== null) payload.value=value;
    return payload;
  }
  function command(action, value) {
    cancelHoverPreview();
    var payload=selectionPayload(action,value);
    if(!payload) return;
    send(payload);
  }
  function icon(name) {
    var ns='http://www.w3.org/2000/svg', svg=document.createElementNS(ns,'svg');
    svg.setAttribute('viewBox','0 0 24 24'); svg.setAttribute('width','22'); svg.setAttribute('height','22');
    svg.setAttribute('aria-hidden','true'); svg.setAttribute('focusable','false');
    var paths={
      unordered:'M8 6h12M8 12h12M8 18h12M3 6h1M3 12h1M3 18h1',
      ordered:'M9 6h12M9 12h12M9 18h12M3 3h1v5M2 11c3-2 4 1 0 4h4M2 18h3l-2 2h2v2H2',
      tasks:'M9 6h12M9 12h12M9 18h12M2 4h4v4H2zM2 10h4v4H2zM2 16h4v4H2zM2 12l1 1 3-3',
      quote:'M4 8h5v6H4v-3l3-5M14 8h5v6h-5v-3l3-5',
      code:'M8 7l-5 5 5 5M16 7l5 5-5 5M14 4l-4 16',
      'code-block':'M3 3h18v18H3zM9 8l-4 4 4 4M15 8l4 4-4 4',
      link:'M10 14l4-4M8 16l-2 2a4 4 0 0 1-5-5l5-5a4 4 0 0 1 5 0M16 8l2-2a4 4 0 0 1 5 5l-5 5a4 4 0 0 1-5 0',
      clear:'M4 5h13M10 5v14M6 19h8M17 14l5 7M22 14l-5 7',
      edit:'M4 16L16 4l4 4L8 20H4zM13 7l4 4',
      'no-container':'M3 7V3h4M17 3h4v4M21 17v4h-4M7 21H3v-4M6 6l12 12',
      'callout-note':'M3 3h18v18H3zM12 11v6M12 7h.01',
      'callout-tip':'M3 3h18v18H3zM9 15v-2a4 4 0 1 1 6 0v2zM10 18h4',
      'callout-warning':'M3 3h18v18H3zM12 6v8M12 18h.01',
      'callout-important':'M3 3h18v18H3zM12 6l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z',
      'callout-caution':'M3 3h18v18H3zM12 6l7 12H5zM12 11v3M12 16h.01',
      'align-left':'M3 5h18M3 10h12M3 15h18M3 20h12',
      'align-center':'M3 5h18M6 10h12M3 15h18M6 20h12',
      'align-right':'M3 5h18M9 10h12M3 15h18M9 20h12',
      toggle:'M3 5l4 4-4 4M11 5h10M11 11h10M3 18h18'
    };
    var heading=/^(?:toggle-)?h([1-6])$/.exec(name);
    var glyph={paragraph:'¶',bold:'B',italic:'I',underline:'U',strike:'S',math:'∑','math-block':'∑'}[name];
    if(heading || glyph) {
      var text=document.createElementNS(ns,'text'); text.textContent=heading?'H'+heading[1]:glyph;
      text.setAttribute('x',heading && name.indexOf('toggle-')===0?'6':'12'); text.setAttribute('y','18');
      text.setAttribute('text-anchor',heading && name.indexOf('toggle-')===0?'start':'middle');
      text.setAttribute('fill','currentColor'); text.setAttribute('font-size',heading?'15':'20');
      text.setAttribute('font-family','-apple-system,sans-serif');
      if(name==='bold') text.setAttribute('font-weight','700');
      if(name==='italic') text.setAttribute('font-style','italic');
      svg.appendChild(text);
    }
    var drawing=paths[name];
    if(name==='underline') drawing='M5 21h14';
    if(name==='strike') drawing='M3 12h18';
    if(name==='math-block') drawing='M2 2h20v20H2z';
    if(heading && name.indexOf('toggle-')===0) drawing='M1 8l3 4-3 4';
    if(drawing) {
      var path=document.createElementNS(ns,'path'); path.setAttribute('d',drawing);
      path.setAttribute('fill','none'); path.setAttribute('stroke','currentColor');
      path.setAttribute('stroke-width','1.6'); path.setAttribute('stroke-linecap','round'); path.setAttribute('stroke-linejoin','round');
      svg.appendChild(path);
    }
    return svg;
  }
  function button(title, action, style, iconName, parent) {
    var b=document.createElement('button'); b.type='button';
    if(iconName===false) b.textContent=title; else b.appendChild(icon(iconName || style));
    b.setAttribute('aria-label',title); b.setAttribute('title',title);
    if(style) b.setAttribute('data-mp-style',style);
    if(style || iconName==='clear') b.setAttribute('data-mp-inline','');
    listen(b,'click',action); (parent || panel).appendChild(b);
    return b;
  }
  function formatMenu(blockOptions, containerOptions) {
    var opener=button('Type de ligne et encadré',function(){
      openMenu();
    },null,false);
    opener.textContent='';
    var openerLabel=document.createElement('span'); openerLabel.setAttribute('data-mp-format-label','');
    openerLabel.textContent='Texte normal'; opener.appendChild(openerLabel);
    opener.setAttribute('data-mp-format-menu',''); opener.setAttribute('aria-haspopup','menu');
    opener.setAttribute('aria-expanded','false'); opener.setAttribute('aria-controls','macdown-preview-format-options');
    var menu=document.createElement('div'); menu.id='macdown-preview-format-options'; menu.hidden=true;
    menu.setAttribute('role','menu'); menu.setAttribute('aria-label','Type de ligne et encadré');
    function group(scope,label,options) {
      var group=document.createElement('div'); group.setAttribute('role','group'); group.setAttribute('aria-label',label);
      group.setAttribute('data-mp-scope',scope); menu.appendChild(group);
      options.forEach(function(item){
        var choice=button(item[0],function(){
          closeMenu(); command('block',item[1]);
        },null,item[1],group);
        var label=document.createElement('span'); label.textContent=item[0]; choice.appendChild(label);
        choice.setAttribute('data-mp-option',item[1]); choice.setAttribute('role','menuitemradio');
        choice.setAttribute('aria-checked','false');
        choice.disabled=(item[1]==='math-block' && !config.math) || (item[1]==='tasks' && !config.tasks) || (item[1]==='code-block' && !config.fenced);
        listen(choice,'mouseenter',function(){if(!choice.disabled) previewFormatting('block',item[1]);});
        listen(choice,'mouseleave',cancelHoverPreview);
        listen(choice,'focus',function(){if(!choice.disabled) previewFormatting('block',item[1]);});
        listen(choice,'blur',cancelHoverPreview);
      });
    }
    group('block','Type de ligne',blockOptions);
    if(config.math) {
      var equation=button('Équation en ligne',function(){closeMenu();command('math');},'math','math',menu.querySelector('[data-mp-scope=block]'));
      var equationLabel=document.createElement('span');equationLabel.textContent='Équation en ligne';equation.appendChild(equationLabel);
      listen(equation,'mouseenter',function(){previewFormatting('math');});
      listen(equation,'mouseleave',cancelHoverPreview);
      listen(equation,'focus',function(){previewFormatting('math');});
      listen(equation,'blur',cancelHoverPreview);
    }
    var separator=document.createElement('div'); separator.setAttribute('role','separator'); menu.appendChild(separator);
    group('container','Encadré et menu dépliant',containerOptions);
    panel.appendChild(menu);
    function openMenu() {
      clearTimeout(menuTimer);
      menu.hidden=false; opener.setAttribute('aria-expanded','true'); positionPanel();
    }
    function leaveMenu(event) {
      if(event.relatedTarget && (menu.contains(event.relatedTarget) || opener.contains(event.relatedTarget))) return;
      clearTimeout(menuTimer); menuTimer=setTimeout(closeMenu,150);
    }
    listen(opener,'mouseenter',openMenu);
    listen(menu,'mouseenter',function(){clearTimeout(menuTimer);});
    listen(opener,'mouseleave',leaveMenu);
    listen(menu,'mouseleave',leaveMenu);
    listen(menu,'keydown',function(event){
      var choices=Array.from(menu.querySelectorAll('button:not(:disabled)')), index=choices.indexOf(document.activeElement), target;
      if(event.key==='Escape') {closeMenu();opener.focus();event.preventDefault();return;}
      if(event.key==='ArrowRight' || event.key==='ArrowDown') target=(index+1)%choices.length;
      else if(event.key==='ArrowLeft' || event.key==='ArrowUp') target=(index+choices.length-1)%choices.length;
      else if(event.key==='Home') target=0;
      else if(event.key==='End') target=choices.length-1;
      if(target!==undefined && choices.length) {event.preventDefault();choices[target].focus();}
    });
    listen(opener,'keydown',function(event){
      if(event.key==='ArrowDown') {event.preventDefault();openMenu();menu.querySelector('button:not(:disabled)').focus();}
    });
  }
  function createPanel() {
    panel = retainedPanel || document.createElement('div'); panel.id = 'macdown-preview-format';
    panel.className=panelClass;
    panel.setAttribute('data-mp-preview-ui',config.token);
    var previousStyle = retainedPanel ? retainedPanel.style.cssText : null;
    panel.textContent = '';
    panel.setAttribute('role','toolbar'); panel.setAttribute('aria-label','Mise en forme du texte sélectionné');
    panel.style.cssText = 'position:fixed;box-sizing:border-box;display:none;z-index:2147483647;background:#292929;color:#fff;border:1px solid #666;border-radius:8px;padding:8px;box-shadow:0 4px 20px #0005;width:344px;max-width:calc(100vw - 24px);max-height:calc(100vh - 16px);overflow:visible;font:13px -apple-system,sans-serif;';
    if(previousStyle) panel.style.cssText=previousStyle;
    listen(panel,'mousedown',function(e){ if(e.target.closest('button')) e.preventDefault(); });
    var defaultCalloutTitles={note:'Note',tip:'Tip',warning:'Warning',important:'Important',caution:'Caution'};
    var calloutOptions=calloutTypes.map(function(type){
      var title=config.calloutTitles && config.calloutTitles[type];
      return ['Encadré — '+(typeof title==='string' && title.length ? title : defaultCalloutTitles[type]),'callout-'+type];
    });
    formatMenu([
      ['Texte normal','paragraph'],['Titre 1','h1'],['Titre 2','h2'],['Titre 3','h3'],['Titre 4','h4'],['Titre 5','h5'],['Titre 6','h6'],
      ['Liste à puces','unordered'],['Liste numérotée','ordered'],['Liste de tâches','tasks'],
      ['Citation','quote'],['Code — bloc','code-block'],['Équation — bloc','math-block']
    ],[
      ['Aucun encadré','no-container']
    ].concat(calloutOptions,[
      ['Menu dépliant','toggle'],
      ['Titre dépliant 1','toggle-h1'],['Titre dépliant 2','toggle-h2'],['Titre dépliant 3','toggle-h3'],['Titre dépliant 4','toggle-h4']
    ]));
    button('Gras',function(){command('bold');},'bold');
    button('Italique',function(){command('italic');},'italic');
    button('Souligné',function(){command('underline');},'underline');
    if(config.strike) button('Barré',function(){command('strike');},'strike');
    button('Code',function(){command('code');},'code');
    button('Retirer les styles',function(){command('clear');},null,'clear');
    button('Lien',function(){var url=window.prompt('Adresse du lien (https://…)','https://');if(url) command('link',url);},'link');
    var editButton=button('Modifier le texte',function(){
      if(!saved || (saved.runs && saved.runs.length!==1)) return;
      var span=mappedSpan(saved.id);
      if(span && span.closest('code')) return;
      hide(); if(span) begin(span);
    },null,'edit');
    editButton.setAttribute('data-mp-edit-text','');
    var alignmentRow=document.createElement('div');
    alignmentRow.setAttribute('data-mp-table-alignment',''); alignmentRow.hidden=true;
    alignmentRow.setAttribute('role','group'); alignmentRow.setAttribute('aria-label','Alignement des colonnes');
    [['Gauche','left'],['Centrer','center'],['Droite','right']].forEach(function(item){
      var control=button(item[0],function(){command('table-align',item[1]);},null,'align-'+item[1],alignmentRow);
      control.setAttribute('data-mp-align',item[1]);
    });
    panel.appendChild(alignmentRow);
    panel.appendChild(panel.querySelector('[role="menu"]'));
    panelStyle = retainedUI ? retainedUI.style : document.createElement('style'); panelStyle.id='macdown-preview-edit-style';
    var selector='.'+panelClass;
    panelStyle.textContent=selector+' [data-mp-table-alignment]{border-top:1px solid #666;margin:4px 2px 0;padding-top:4px} '+selector+' [data-mp-table-alignment][hidden]{display:none!important} '+selector+' button{font:inherit;color:#fff;background:#3c3c3c;border:1px solid #666;border-radius:4px;margin:2px;padding:6px;cursor:pointer;vertical-align:middle;width:36px;height:36px} '+selector+' svg{display:block;pointer-events:none} '+selector+' button:disabled{opacity:.5;cursor:default} '+selector+' [aria-pressed="true"],'+selector+' [data-mp-active]{color:#2784DE} '+selector+' [role="menu"]{position:absolute;box-sizing:border-box;width:260px;max-width:calc(100vw - 24px);max-height:calc(100vh - 16px);overflow:auto;background:#292929;color:#fff;border:1px solid #666;border-radius:8px;padding:8px;box-shadow:0 4px 20px #0005;margin:0} '+selector+' [role="menu"][hidden]{display:none!important} '+selector+' [data-mp-format-menu]{box-sizing:border-box;display:flex;align-items:center;gap:8px;width:calc(100% - 4px);text-align:left;font-size:16px;line-height:22px} '+selector+' [data-mp-format-label]{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis} '+selector+' [data-mp-format-menu]::after{content:"";display:block;flex-shrink:0;width:6px;height:6px;margin-right:3px;border-top:2px solid currentColor;border-right:2px solid currentColor;transform:rotate(45deg)} '+selector+' [role="group"]{display:block} '+selector+' [role="menu"] button{display:flex;align-items:center;gap:10px;width:calc(100% - 4px);height:auto;min-height:36px;text-align:left} '+selector+' [role="menu"] svg{flex-shrink:0} '+selector+' [role="separator"]{border-top:1px solid #666;margin:8px 2px} '+selector+' button:focus-visible{outline:2px solid #2784DE;outline-offset:1px} .'+runClass+'[contenteditable]{outline:2px solid #4385be;outline-offset:3px} @media print{'+selector+'{display:none!important}}';
    document.body.appendChild(panelStyle); document.body.appendChild(panel);
  }
  function begin(span) {
    if (active === span) return;
    if (/[\r\n]/.test(span.textContent)) { showEditError('Ce passage contient plusieurs lignes source. Modifiez-le dans l’éditeur de gauche.'); return; }
    if (active) { commit(); return; }
    active = span; hide(); saved = null;
    span._mpOriginal = span.textContent;
    span.setAttribute('contenteditable','true'); span.focus();
    var range=document.createRange(); range.selectNodeContents(span);
    var selection=window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
  }
  config.nodes.forEach(function (item) {
    var node = window.__macdownPreviewEditNodes[item.node];
    if (!node || !node.parentNode || node.nodeValue !== item.text) return;
    var span=document.createElement('span'); span.setAttribute('data-mp-edit-id',String(item.id));
    span.className=runClass;
    span._mpID=item.id; span.setAttribute('title','Sélectionner pour mettre en forme ou choisir Modifier le texte.');
    node.parentNode.replaceChild(span,node); span.appendChild(node);
    mappedSpans.push(span);
    listen(span,'blur',commit);
    listen(span,'keydown',function(e){
      if(e.isComposing) return;
      if(e.key === 'Escape'){e.preventDefault();span.textContent=span._mpOriginal;active=null;span.removeAttribute('contenteditable');hide();send({action:'refresh'});}
      else if(e.key === 'Enter'){e.preventDefault();commit();}
    });
    listen(span,'beforeinput',function(e){if(e.inputType && e.inputType.indexOf('format')===0)e.preventDefault();});
    listen(span,'paste',function(e){e.preventDefault();document.execCommand('insertText',false,e.clipboardData.getData('text/plain').replace(/[\r\n]+/g,' '));});
    listen(span,'drop',function(e){e.preventDefault();});
  });
  delete window.__macdownPreviewEditNodes;
  createPanel();
  function updateStyles(selected) {
    var runs=selected ? (selected.runs || [selected]) : [];
    var spans=runs.map(function(run){return mappedSpan(run.id);});
    // Fenced code is literal block content; its structure remains editable via
    // both selectors. Inline code can itself be wrapped by emphasis or a link,
    // with those markers outside the backticks rather than inside the literal.
    var cells=spans.map(function(span){return span && span.closest('td,th');});
    var table=cells[0] && cells[0].closest('table');
    var inTable=!!table && cells.every(function(cell){return cell && cell.closest('table')===table;});
    var alignmentRow=panel.querySelector('[data-mp-table-alignment]');
    alignmentRow.hidden=!inTable;
    alignmentRow.querySelectorAll('[data-mp-align]').forEach(function(control){
      var requested=control.getAttribute('data-mp-align');
      control.setAttribute('aria-pressed',String(inTable && cells.every(function(cell){
        var alignment=cell.style.textAlign || cell.getAttribute('align') || 'left';
        return alignment===requested;
      })));
    });
    var containsCodeBlock=spans.some(function(span){return !!(span && span.closest('pre'));});
    panel.querySelectorAll('button[data-mp-inline]').forEach(function(control){control.disabled=containsCodeBlock;});
    var selectors={bold:'strong,b',italic:'em,i',underline:'u',strike:'del,s,strike',code:'code',link:'a[href]',math:'.MathJax,.MathJax_Display'};
    panel.querySelectorAll('[data-mp-style]').forEach(function(control){
      var style=control.getAttribute('data-mp-style'), selector=selectors[style];
      var eligible=spans.filter(function(span,index){
        return style!=='code' || (span && span.textContent.substring(runs[index].start,runs[index].end).trim().length>0);
      });
      control.setAttribute('aria-pressed',String(!containsCodeBlock && eligible.length>0 && eligible.every(function(span){return !!(span && span.closest(selector));})));
    });
    function blockType(span) {
      if(!span) return '';
      if(span.closest('pre')) return 'code-block';
      if(span.closest('.MathJax_Display')) return 'math-block';
      // A heading inside a container is still a heading. Inspect its nearest
      // content element instead of allowing the outer callout to mask it.
      var block=span.closest('h1,h2,h3,h4,h5,h6,li,blockquote,p');
      if(!block) return '';
      if(/^H[1-6]$/.test(block.tagName)) return block.tagName.toLowerCase();
      if(block.tagName==='LI' || block.tagName==='P') {
        var item=span.closest('li'), list=item && item.closest('ol,ul');
        if(item && list) {
          var task=Array.from(item.querySelectorAll('input[type="checkbox"]')).some(function(input){return input.closest('li')===item;});
          return task?'tasks':list.tagName==='OL'?'ordered':'unordered';
        }
      }
      if(span.closest('blockquote')) return 'quote';
      return block.tagName==='P'?'paragraph':'';
    }
    function containerType(span) {
      if(!span) return '';
      var container=span.closest('.mp-callout,details');
      if(!container) return 'no-container';
      if(container.tagName==='DETAILS') {
        var summary=Array.from(container.children).find(function(child){return child.tagName==='SUMMARY';});
        var heading=summary && summary.querySelector('h1,h2,h3,h4');
        return heading?'toggle-'+heading.tagName.toLowerCase():'toggle';
      }
      var type=calloutTypes.find(function(name){return container.classList.contains('mp-callout-'+name);});
      return type?'callout-'+type:'';
    }
    function updateMenu(scope, typeForSpan) {
      var common=spans.length?typeForSpan(spans[0]):'';
      if(!spans.every(function(span){return typeForSpan(span)===common;})) common='';
      var group=panel.querySelector('[data-mp-scope="'+scope+'"]');
      group.querySelectorAll('[data-mp-option]').forEach(function(option){
        var matches=!!common && option.getAttribute('data-mp-option')===common;
        option.setAttribute('aria-checked',String(matches));
        if(matches) option.setAttribute('data-mp-active',''); else option.removeAttribute('data-mp-active');
      });
    }
    panel.querySelector('[data-mp-edit-text]').disabled=containsCodeBlock || runs.length!==1 || !!(spans[0] && spans[0].closest('code'));
    updateMenu('block',blockType);
    updateMenu('container',containerType);
    var current=panel.querySelector('[data-mp-scope=block] [data-mp-option][data-mp-active]');
    var opener=panel.querySelector('[data-mp-format-menu]');
    opener.querySelector('[data-mp-format-label]').textContent=current ? current.getAttribute('aria-label') : 'Type de ligne';
    if(current) opener.setAttribute('data-mp-active',''); else opener.removeAttribute('data-mp-active');
  }
  function updatePanel() {
    if(active || rendering || selectingWithMouse || hoverPreview) return;
    var selected=currentSelection();
    if(errorMessage && JSON.stringify(selected)!==errorSelection) {
      errorMessage.remove(); errorMessage=null; errorSelection=null;
    }
    if(!selected){if(!panel.contains(document.activeElement)){saved=null;hide();}return;}
    if(panel.style.display==='none' || JSON.stringify(saved)!==JSON.stringify(selected)) closeMenu();
    saved=selected; updateStyles(selected);
    panel.style.display='block'; positionPanel();
  }
  function setPreviewScale(scale) {
    // Page zoom magnifies the document; controls stop growing at 100%.
    // Scale only the controls, keeping document zoom and source text intact.
    if(typeof scale!=='number' || !Number.isFinite(scale) || scale<=0) return;
    config.previewScale=scale; uiZoom=1/Math.max(1,scale);
    panel.style.transform='scale('+uiZoom+')';
    panel.style.transformOrigin='0 0';
    updatePanel();
  }
  function positionPanel() {
    var selection=window.getSelection();
    if(!selection || !selection.rangeCount) return;
    var viewportWidth=window.innerWidth/uiZoom, viewportHeight=window.innerHeight/uiZoom;
    panel.style.maxWidth=Math.max(0,viewportWidth-24)+'px';
    panel.style.maxHeight=Math.max(0,viewportHeight-16)+'px';
    // Match the selector to the visible icon rows, including narrow viewports
    // and configurations that omit the strikethrough button.
    var opener=panel.querySelector('[data-mp-format-menu]');
    var iconButtons=Array.from(panel.children).filter(function(child){return child.tagName==='BUTTON' && child!==opener;});
    var iconsRight=Math.max.apply(null,iconButtons.map(function(button){return button.getBoundingClientRect().right;}));
    if(iconButtons.length) opener.style.width=Math.max(0,(iconsRight-opener.getBoundingClientRect().left)/uiZoom)+'px';
    function uiRect(rect) {
      return {left:rect.left/uiZoom,right:rect.right/uiZoom,top:rect.top/uiZoom,bottom:rect.bottom/uiZoom};
    }
    var rect=uiRect(selection.getRangeAt(0).getBoundingClientRect());
    var menuWidth=Math.min(260,Math.max(220,viewportWidth-panel.offsetWidth-24));
    var reservedWidth=panel.offsetWidth+menuWidth<=viewportWidth-24 ? menuWidth : 0;
    panel.style.left=(Math.max(12,Math.min(rect.left,viewportWidth-panel.offsetWidth-reservedWidth-12))*uiZoom)+'px';
    panel.style.top=(Math.max(8,Math.min(rect.bottom+8,viewportHeight-panel.offsetHeight-8))*uiZoom)+'px';
    var menu=panel.querySelector('[role=menu]');
    if(menu.hidden) return;
    // Keep the compact toolbar unchanged. Prefer a touching right-hand menu,
    // then the left side; narrow viewports use a separate surface below it.
    menu.style.width=menuWidth+'px';
    menu.style.maxWidth=Math.max(0,viewportWidth-24)+'px';
    menu.style.maxHeight=(viewportHeight-16)+'px';
    var bounds=uiRect(panel.getBoundingClientRect()), width=menu.offsetWidth, left, top=bounds.top;
    if(bounds.right+width<=viewportWidth-12) left=bounds.right;
    else if(bounds.left-width>=12) left=bounds.left-width;
    else {
      var pairWidth=panel.offsetWidth+width;
      if(pairWidth<=viewportWidth-24) {
        panel.style.left=((viewportWidth-pairWidth-12)*uiZoom)+'px';
        bounds=uiRect(panel.getBoundingClientRect()); left=bounds.right;
      } else {
        left=Math.max(12,Math.min(bounds.left,viewportWidth-width-12));
        var below=viewportHeight-bounds.bottom-8, above=bounds.top-8;
        if(below>=above) {top=bounds.bottom;menu.style.maxHeight=Math.max(0,below)+'px';}
        else {menu.style.maxHeight=Math.max(0,above)+'px';top=bounds.top-menu.offsetHeight;}
      }
    }
    menu.style.left=(left-bounds.left-panel.clientLeft)+'px';
    menu.style.top=(Math.max(8,Math.min(top,viewportHeight-menu.offsetHeight-8))-bounds.top-panel.clientTop)+'px';
  }
  listen(document,'selectionchange',function(){
    clearTimeout(timer); timer=setTimeout(updatePanel,120);
  });
  listen(document,'keydown',function(event){
    if(event.key==='Escape' && !panel.querySelector('[role=menu]').hidden) {
      closeMenu(); event.preventDefault();
    }
  });
  // Force Touch prepares a native word lookup before mousedown. Suppress
  // that transient highlight on editable preview prose, without cancelling
  // the ordinary click/drag events or link previews and explicit text edits.
  listen(document,'webkitmouseforcewillbegin',function(event){
    if(!active && !panel.contains(event.target) && event.target.closest('.'+runClass) &&
      !event.target.closest('a,button,input,textarea,select,[contenteditable]')) event.preventDefault();
  });
  listen(document,'mousedown',function(event){
    if(event.button!==0 || panel.contains(event.target)) return;
    cancelHoverPreview();
    // WebKit retains an existing word selection on press to start a text
    // drag. A fresh single press on the preview page, including its blank
    // background, must start a new selection. Leave multi-click and modifiers native.
    if(!active && event.detail===1 && !event.shiftKey && !event.metaKey &&
      !event.ctrlKey && !event.altKey &&
      !event.target.closest('a,button,input,textarea,select,[contenteditable]')) {
      window.getSelection().removeAllRanges();
    }
    selectingWithMouse=true; clearTimeout(timer); saved=null; hide();
  });
  function finishMouseSelection() {
    if(!selectingWithMouse) return;
    selectingWithMouse=false; clearTimeout(timer); updatePanel();
  }
  listen(window,'mouseup',finishMouseSelection);
  listen(window,'blur',function(){
    closeMenu();
    if(!selectingWithMouse) return;
    selectingWithMouse=false; clearTimeout(timer); saved=null; hide();
  });
  listen(window,'scroll',function(){if(!rendering) updatePanel();});
  listen(window,'resize',updatePanel);
  function showEditError(text) {
    errorSelection=JSON.stringify(currentSelection() || saved);
    panel.style.display='block'; panel.style.left='12px'; panel.style.top='12px';
    if(!errorMessage){errorMessage=document.createElement('div');errorMessage.id='macdown-preview-edit-error';panel.insertBefore(errorMessage,panel.firstChild);}
    errorMessage.textContent=text;
  }
  function restoreSelection(selected) {
    if(!selected) return;
    var runs=selected.runs || [selected], spans=[];
    if(!runs.length || !runs.every(function(run){
      var span=mappedSpan(run.id);
      if(!span || !span.firstChild || span.firstChild.nodeType!==3 ||
        !Number.isInteger(run.start) || !Number.isInteger(run.end) ||
        run.start<0 || run.end>span.textContent.length || run.end<=run.start ||
        (spans.length && !(spans[spans.length-1].compareDocumentPosition(span)&4))) return false;
      spans.push(span); return true;
    })) return;
    var range=document.createRange();
    range.setStart(spans[0].firstChild,runs[0].start);
    range.setEnd(spans[spans.length-1].firstChild,runs[runs.length-1].end);
    var table=spans[0].closest('table');
    var inTable=table && spans.every(function(span){return span.closest('td,th') && span.closest('table')===table;});
    function normalize(text){return inTable ? text.replace(/\s/g,'') : normalizedSelectionText(text);}
    if(selected.text!==undefined && normalize(range.toString())!==normalize(selected.text)) return;
    var selection=window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
    saved=currentSelection();
    updatePanel();
  }
  function normalizedSelectionText(text) {
    return text.replace(/\r\n?/g,'\n').replace(/\n+/g,'\n');
  }
  window.macdownPreviewEditor={elements:function(){return {panel:panel,style:panelStyle,spans:mappedSpans.slice()};},clearSelection:clearSelection,prepareForRender:function(){cancelHoverPreview();saved=currentSelection() || saved;rendering=true;clearTimeout(timer);},draft:draft,finish:finish,selectionPayload:selectionPayload,setPreviewScale:setPreviewScale,showError:function(){
    showEditError('Modification refusée : la source a changé. Copiez votre texte, puis appuyez sur Échap pour annuler.');
  },showFormattingError:function(){
    showEditError('Mise en forme refusée : cette sélection ne peut pas être représentée correctement en Markdown. Sélectionnez un passage plus court.');
  },destroy:function(preservePanel){
    cancelHoverPreview();
    clearTimeout(timer); clearTimeout(menuTimer); active=null;
    handlers.forEach(function(h){h[0].removeEventListener(h[1],h[2],false);});
    if(!preservePanel && panel && panel.parentNode) panel.parentNode.removeChild(panel);
    if(panelStyle && !preservePanel)panelStyle.remove();
  }};
  setPreviewScale(config.previewScale || 1);
  restoreSelection(config.selection);
  updatePanel();
})();
