'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Exercise our DOM adapter with a controlled renderer rejection. Mermaid
// itself is deliberately not mocked as a security guarantee for its SVGs.
(async function () {
  let onLoad;
  let replacement;
  const pre = { tagName: 'PRE', parentNode: {
    replaceChild(element, original) {
      assert.equal(original, pre);
      replacement = element;
    }
  } };
  const code = { textContent: 'invalid graph', parentElement: pre };
  const message = '<img src=x onerror=alert(1)>';
  const context = {
    document: {
      readyState: 'complete', body: { contains: node => node === pre },
      querySelectorAll: () => [code],
      createElement: (tag) => ({ tagName: tag, style: {} })
    },
    window: { addEventListener: (event, callback) => { onLoad = callback; } },
    console: { warn() {}, error() {} },
    mermaid: { initialize() {}, async render() { throw new Error(message); } }
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,
    '../../MacDown/Resources/Extensions/mermaid.init.js'), 'utf8'), context);
  await onLoad();
  assert.equal(replacement.tagName, 'pre');
  assert.equal(replacement.textContent, 'Mermaid Error: ' + message);
  assert.equal(replacement.innerHTML, undefined);
  assert.equal(pre.outerHTML, undefined);
  process.stdout.write('Mermaid error text boundary: passed\n');
})().catch(error => { console.error(error); process.exitCode = 1; });

(async function () {
  let onLoad, onMutation, scheduled, resolveOld;
  const oldPre = { tagName: 'PRE' };
  const newPre = { tagName: 'PRE' };
  let currentPre = oldPre;
  let code = { textContent: 'old graph', parentElement: oldPre };
  const rendered = [];
  const context = {
    document: {
      readyState: 'complete',
      body: { contains: node => node === currentPre },
      querySelectorAll: () => code ? [code] : [],
      createElement: () => ({ style: {} })
    },
    window: { addEventListener: (event, callback) => { onLoad = callback; } },
    console: { warn() {}, error() {} },
    setTimeout: callback => { scheduled = callback; },
    MutationObserver: class {
      constructor(callback) { onMutation = callback; }
      observe() {}
    },
    mermaid: {
      initialize() {},
      render(id, source) {
        rendered.push(source);
        if (source === 'old graph') return new Promise(resolve => { resolveOld = resolve; });
        code = null;
        return Promise.resolve({ svg: '<svg>new graph</svg>' });
      }
    }
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,
    '../../MacDown/Resources/Extensions/mermaid.init.js'), 'utf8'), context);
  const oldRender = onLoad();
  currentPre = newPre;
  code = { textContent: 'new graph', parentElement: newPre };
  onMutation();
  resolveOld({ svg: '<svg>old graph</svg>' });
  await oldRender;
  assert.equal(oldPre.outerHTML, undefined);
  assert.equal(typeof scheduled, 'function');
  await scheduled();
  assert.deepEqual(rendered, ['old graph', 'new graph']);
  assert.equal(newPre.outerHTML, '<svg>new graph</svg>');
  process.stdout.write('Mermaid replaced DOM during pending render: passed\n');
})().catch(error => { console.error(error); process.exitCode = 1; });
