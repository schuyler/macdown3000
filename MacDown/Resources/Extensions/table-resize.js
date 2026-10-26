/**
 * Live-preview Markdown table column resizing.
 *
 * Widths are ephemeral: kept only in this script's in-memory sessionWidths
 * map, never written back to the document or persisted to disk. They survive
 * incremental preview updates (typing) because the preview's JS context
 * persists across DOM replacement, but reset on a full preview reload.
 * This script only runs in the editor preview; exports do not include it.
 */
(function () {
  var MIN_WIDTH = 48;
  var resizing = null;
  var sessionWidths = {};

  function headerText(table) {
    var cells = table.querySelectorAll('thead th');
    if (!cells.length) {
      cells = table.querySelectorAll('tr:first-child th, tr:first-child td');
    }
    var parts = [];
    for (var i = 0; i < cells.length; i++) {
      parts.push((cells[i].textContent || '').replace(/\s+/g, ' ').trim());
    }
    return parts.join('|');
  }

  function hashString(value) {
    var hash = 2166136261;
    for (var i = 0; i < value.length; i++) {
      hash ^= value.charCodeAt(i);
      hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
    }
    return (hash >>> 0).toString(16);
  }

  function tableKey(table, index) {
    return index + ':' + hashString(headerText(table));
  }

  function ensureColgroup(table, columnCount) {
    var colgroup = table.querySelector('colgroup');
    if (!colgroup) {
      colgroup = document.createElement('colgroup');
      table.insertBefore(colgroup, table.firstChild);
    }
    while (colgroup.children.length < columnCount) {
      colgroup.appendChild(document.createElement('col'));
    }
    while (colgroup.children.length > columnCount) {
      colgroup.removeChild(colgroup.lastChild);
    }
    return colgroup;
  }

  function setColumnWidth(col, width) {
    col.style.width = Math.max(MIN_WIDTH, Math.round(width)) + 'px';
  }

  function headerCells(table) {
    var cells = table.querySelectorAll('thead th');
    if (cells.length) {
      return cells;
    }
    return table.querySelectorAll('tr:first-child th, tr:first-child td');
  }

  function teardownHandles(table) {
    var oldHandles = table.querySelectorAll('.macdown-table-resize-handle');
    for (var i = 0; i < oldHandles.length; i++) {
      oldHandles[i].parentNode.removeChild(oldHandles[i]);
    }
    var oldCells = table.querySelectorAll('.macdown-table-resizable');
    for (var j = 0; j < oldCells.length; j++) {
      oldCells[j].classList.remove('macdown-table-resizable');
    }
  }

  function initTable(table, index) {
    var cells = headerCells(table);
    if (!cells.length) {
      return;
    }

    teardownHandles(table);

    var key = tableKey(table, index);
    table.setAttribute('data-macdown-table-key', key);
    table.classList.add('macdown-resizable-table');

    var colgroup = ensureColgroup(table, cells.length);
    var saved = sessionWidths[key] || {};
    for (var i = 0; i < cells.length; i++) {
      var savedWidth = saved[String(i)];
      if (savedWidth !== undefined && savedWidth !== null) {
        setColumnWidth(colgroup.children[i], savedWidth);
      }
    }

    for (var column = 0; column < cells.length; column++) {
      (function (cell, columnIndex) {
        cell.classList.add('macdown-table-resizable');
        var handle = document.createElement('span');
        handle.className = 'macdown-table-resize-handle';
        handle.setAttribute('role', 'separator');
        handle.setAttribute('aria-orientation', 'vertical');
        handle.setAttribute('title', 'Resize column');

        handle.addEventListener('mousedown', function (event) {
          event.preventDefault();
          event.stopPropagation();
          var col = colgroup.children[columnIndex];
          var rect = cell.getBoundingClientRect();
          resizing = {
            table: key,
            column: columnIndex,
            col: col,
            startX: event.clientX,
            startWidth: parseFloat(col.style.width) || rect.width
          };
          document.documentElement.classList.add('macdown-table-resizing');
        });

        handle.addEventListener('dblclick', function (event) {
          event.preventDefault();
          event.stopPropagation();
          colgroup.children[columnIndex].style.width = '';
          var tableWidths = sessionWidths[key];
          if (tableWidths) {
            delete tableWidths[String(columnIndex)];
            if (!Object.keys(tableWidths).length) {
              delete sessionWidths[key];
            }
          }
        });

        cell.appendChild(handle);
      })(cells[column], column);
    }
  }

  document.addEventListener('mousemove', function (event) {
    if (!resizing) {
      return;
    }
    var width = Math.max(MIN_WIDTH, resizing.startWidth + event.clientX - resizing.startX);
    setColumnWidth(resizing.col, width);
  });

  document.addEventListener('mouseup', function () {
    if (!resizing) {
      return;
    }
    var width = parseFloat(resizing.col.style.width);
    if (isFinite(width)) {
      var tableWidths = sessionWidths[resizing.table];
      if (!tableWidths) {
        tableWidths = {};
        sessionWidths[resizing.table] = tableWidths;
      }
      tableWidths[String(resizing.column)] = width;
    }
    resizing = null;
    document.documentElement.classList.remove('macdown-table-resizing');
  });

  window.macdownInitTableResize = function () {
    var tables = document.querySelectorAll('table');
    for (var i = 0; i < tables.length; i++) {
      initTable(tables[i], i);
    }
  };

  window.macdownInitTableResize();
})();
