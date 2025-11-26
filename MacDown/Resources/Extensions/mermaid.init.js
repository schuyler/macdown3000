// init mermaid
// Updated for Mermaid 11.x (GitHub issue #35)

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
    securityLevel: 'loose',
    logLevel: 'error'
  });

  // Generate unique ID to avoid collisions on re-renders
  var renderCount = 0;
  var sessionId = Date.now().toString(36) + Math.random().toString(36).substr(2, 5);

  var init = async function() {
    var domAll = document.querySelectorAll(".language-mermaid");
    for (var i = 0; i < domAll.length; i++) {
      var codeElement = domAll[i];
      var graphSource = codeElement.innerText || codeElement.textContent;

      // Navigate to the container element (parent of <pre> or <code>)
      var container = codeElement.parentElement;
      if (container.tagName === "PRE") {
        container = container.parentElement;
      }

      // Generate unique ID to prevent collisions on document re-renders
      var uniqueId = 'mermaid_' + sessionId + '_' + (renderCount++);

      try {
        // Mermaid 11.x uses Promise-based API
        var result = await mermaid.render(uniqueId, graphSource);
        container.innerHTML = result.svg;
      } catch (error) {
        console.error('Mermaid rendering error:', error);
        // Display error message in the container
        container.innerHTML = '<pre style="color: red; padding: 10px; background: #fee;">' +
          'Mermaid Error: ' + error.message + '</pre>';
      }
    }
  };

  if (typeof window.addEventListener != "undefined") {
    window.addEventListener("load", init, false);
  } else {
    window.attachEvent("onload", init);
  }
})();
