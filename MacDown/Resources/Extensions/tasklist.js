/**
 * Interactive Task List Support for MacDown 3000
 *
 * Enables clicking checkboxes in the preview to toggle their state
 * in the source document.
 *
 * Related to GitHub issue #269.
 */
(function () {
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
          window.location = 'x-macdown-checkbox://toggle/' + index;
        }
      });
      break;
    }
  }
})();
