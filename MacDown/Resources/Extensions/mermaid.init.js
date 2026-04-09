// init mermaid
// Updated for Mermaid 11.x (GitHub issue #35)
// MutationObserver for DOM replacement re-rendering (GitHub issue #331)

(function () {

  // Check if mermaid library is loaded
  if (typeof mermaid === 'undefined') {
    console.warn('Mermaid library not loaded');
    return;
  }

  // Use 'forest' theme via API instead of external CSS to fix gantt rendering
  // issues (GitHub issue #18). Mermaid 8.0+ requires theme-based configuration.
  mermaid.initialize({
    startOnLoad: false,
    theme: 'forest',
    flowchart: {
      htmlLabels: false,
      useMaxWidth: true
    },
    securityLevel: 'antiscript',
    logLevel: 'error'
  });

  // Generate unique ID to avoid collisions on re-renders
  var renderCount = 0;
  var sessionId = Date.now().toString(36) + Math.random().toString(36).substr(2, 5);

  // Guard against re-entrant calls (e.g. MutationObserver firing during render).
  // The primary safety net is the domAll.length === 0 check below, which prevents
  // unnecessary re-renders once all .language-mermaid elements have been replaced
  // with SVGs. This flag is an additional belt-and-suspenders measure.
  var rendering = false;

  var init = async function() {
    if (rendering) return;

    var domAll = document.querySelectorAll(".language-mermaid");
    if (domAll.length === 0) return;

    rendering = true;
    try {
      for (var i = 0; i < domAll.length; i++) {
        var codeElement = domAll[i];
        var graphSource = codeElement.innerText || codeElement.textContent;

        // The <code> element is always inside a <pre>. Replace the <pre>
        // directly using outerHTML so that sibling <pre> elements (other
        // diagrams in the same document) are not destroyed. The old code
        // navigated to parentElement.parentElement and set innerHTML on the
        // shared wrapper, which removed all subsequent diagrams from the DOM
        // on the first iteration (GitHub issue #331).
        var pre = codeElement.parentElement;
        if (!pre || pre.tagName !== "PRE") {
          console.warn('Mermaid: unexpected DOM structure, skipping element');
          continue;
        }

        // Generate unique ID to prevent collisions on document re-renders
        var uniqueId = 'mermaid_' + sessionId + '_' + (renderCount++);

        try {
          // Mermaid 11.x uses Promise-based API
          var result = await mermaid.render(uniqueId, graphSource);
          pre.outerHTML = result.svg;
        } catch (error) {
          console.error('Mermaid rendering error:', error);
          // Display error message in place of the <pre>
          pre.outerHTML = '<pre style="color: red; padding: 10px; background: #fee;">' +
            'Mermaid Error: ' + (error.message || error) + '</pre>';
        }
      }
    } finally {
      rendering = false;
    }
  };

  // Initial render on page load
  if (typeof window.addEventListener != "undefined") {
    window.addEventListener("load", init, false);
  } else {
    window.attachEvent("onload", init);
  }

  // Re-render on DOM replacement (GitHub issue #331).
  // When MPDocument.m replaces body.innerHTML, the window.load event does not
  // fire again. A MutationObserver detects new .language-mermaid elements and
  // triggers rendering automatically. After rendering, those elements are
  // replaced with SVGs, so there is no risk of infinite re-trigger loops.
  if (typeof MutationObserver !== 'undefined') {
    var observer = new MutationObserver(function() {
      if (document.querySelectorAll(".language-mermaid").length > 0) {
        init();
      }
    });

    var startObserving = function() {
      if (document.body) {
        observer.observe(document.body, { childList: true, subtree: true });
      }
    };

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', startObserving);
    } else {
      startObserving();
    }
  }
})();
