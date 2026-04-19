/**
 * Interactive Task List Support for MacDown 3000
 *
 * Enables clicking checkboxes in the preview to toggle their state
 * in the source document.
 *
 * Related to GitHub issue #269.
 */
(function () {
  var tokenMeta = document.querySelector('meta[name="macdown-checkbox-token"]');
  var checkboxToken = tokenMeta ? tokenMeta.getAttribute('content') : '';
  var taskListItems = document.getElementsByClassName('task-list-item');
  for (var i = 0; i < taskListItems.length; i++) {
    var inputs = taskListItems[i].getElementsByTagName('input');
    for (var j = 0; j < inputs.length; j++) {
      var input = inputs[j];
      // Enable the checkbox for interaction
      input.disabled = false;
      // Add click handler to toggle checkbox in source
      input.addEventListener('click', function(e) {
        e.preventDefault();
        var checkbox = e.target;
        var index = checkbox.getAttribute('data-checkbox-index');
        if (index !== null) {
          // Navigate to custom URL scheme to trigger Objective-C handler
          var url = 'x-macdown-checkbox://toggle/' + index;
          if (checkboxToken) {
            url += '?token=' + encodeURIComponent(checkboxToken);
          }
          window.location = url;
        }
      });
      break;
    }
  }
})();
