/**
 * Live-preview Markdown table column resizing.
 *
 * Widths are persisted by the native app through x-macdown-table-layout URLs.
 * This script only runs in the editor preview; exports do not include it.
 */
(function () {
  var MIN_WIDTH = 48;
  var resizing = null;

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

  function currentLayouts() {
    var node = document.getElementById('macdown-table-layouts');
    if (!node) {
      return {};
    }
    try {
      return JSON.parse(node.textContent || '{}') || {};
    } catch (e) {
      return {};
    }
  }

  function bridgeToken() {
    var tokenMeta = document.querySelector('meta[name="macdown-table-layout-token"]');
    return tokenMeta ? tokenMeta.getAttribute('content') : '';
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

  function sendLayout(action, table, column, width) {
    var token = bridgeToken();
    if (!token) {
      return;
    }
    var url = 'x-macdown-table-layout://' + action +
      '?token=' + encodeURIComponent(token) +
      '&table=' + encodeURIComponent(table) +
      '&column=' + encodeURIComponent(column);
    if (width !== null && width !== undefined) {
      url += '&width=' + encodeURIComponent(Math.round(width));
    }
    window.location = url;
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

  function initTable(table, index, layouts) {
    var cells = headerCells(table);
    if (!cells.length) {
      return;
    }

    teardownHandles(table);

    var key = tableKey(table, index);
    table.setAttribute('data-macdown-table-key', key);
    table.classList.add('macdown-resizable-table');

    var colgroup = ensureColgroup(table, cells.length);
    var saved = layouts[key] || {};
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
          sendLayout('reset', key, columnIndex, null);
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
      sendLayout('set', resizing.table, resizing.column, width);
    }
    resizing = null;
    document.documentElement.classList.remove('macdown-table-resizing');
  });

  window.macdownInitTableResize = function () {
    var layouts = currentLayouts();
    var tables = document.querySelectorAll('table');
    for (var i = 0; i < tables.length; i++) {
      initTable(tables[i], i, layouts);
    }
  };

  window.macdownInitTableResize();
})();
