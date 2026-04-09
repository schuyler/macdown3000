// graphviz init
// MutationObserver for DOM replacement re-rendering (GitHub issue #332)
(function () {
  var graphviz_engines = ["circo",
                          "dot",
                          "fdp",
                          "neato",
                          "osage",
                          "twopi"];

  function doGraphviz(engine) {
    var domAllDot = document.querySelectorAll("code.language-" + engine);
    for (var i = 0; i < domAllDot.length; i++) {
      var dom = domAllDot[i];
      var graphSource = dom.innerText || dom.textContent;

      // Replace the <pre> directly using outerHTML so that sibling <pre>
      // elements (other diagrams in the same document) are not destroyed.
      // The old code set innerHTML on the shared wrapper two levels up,
      // which removed all subsequent diagrams from the DOM on the first
      // iteration (GitHub issue #332).
      var pre = dom.parentElement;
      if (!pre || pre.tagName !== "PRE") {
        console.warn('Graphviz: unexpected DOM structure, skipping element');
        continue;
      }
      try {
        pre.outerHTML = Viz(graphSource, {engine: engine});
      } catch (e) {
        console.error("Error when parsing node:", dom, e);
      }
    }
  }

  // Guard against re-entrant calls (e.g. MutationObserver firing during render).
  // The primary safety net is the length === 0 check below, which prevents
  // unnecessary re-renders once all .language-{engine} elements have been
  // replaced with SVGs. This flag is an additional belt-and-suspenders measure.
  var rendering = false;

  var init = function() {
    if (rendering) return;

    var hasGraphviz = false;
    for (var e = 0; e < graphviz_engines.length; e++) {
      if (document.querySelectorAll("code.language-" + graphviz_engines[e]).length > 0) {
        hasGraphviz = true;
        break;
      }
    }
    if (!hasGraphviz) return;

    rendering = true;
    try {
      for (var i = 0; i < graphviz_engines.length; i++) {
        doGraphviz(graphviz_engines[i]);
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

  // Re-render on DOM replacement (GitHub issue #332).
  // When MPDocument.m replaces body.innerHTML, the window.load event does not
  // fire again. A MutationObserver detects new .language-{engine} elements and
  // triggers rendering automatically. After rendering, those elements are
  // replaced with SVGs, so there is no risk of infinite re-trigger loops.
  if (typeof MutationObserver !== 'undefined') {
    var observer = new MutationObserver(function() {
      for (var e = 0; e < graphviz_engines.length; e++) {
        if (document.querySelectorAll("code.language-" + graphviz_engines[e]).length > 0) {
          init();
          return;
        }
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
