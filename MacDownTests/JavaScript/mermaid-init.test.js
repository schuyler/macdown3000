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

// R04 places the language class on both PRE and CODE. The adapter's broad
// selector must still render each CODE exactly once and keep sibling diagrams.
(async function () {
  let onLoad, onMutation;
  const scheduled = [];
  const rendered = [];
  const body = { slots: [], contains: node => body.slots.includes(node) };
  const wrapper = { tagName: 'DIV' };
  function diagrams(sources) {
    return sources.map(source => {
      const classes = new Set(['language-mermaid']);
      const pre = {
        tagName: 'PRE', parentElement: wrapper, textContent: source,
        classList: { remove: name => classes.delete(name) }, classes
      };
      pre.code = {
        tagName: 'CODE', textContent: source, parentElement: pre,
        classes: new Set(['language-mermaid'])
      };
      Object.defineProperty(pre, 'outerHTML', {
        set(svg) {
          const index = body.slots.indexOf(pre);
          assert.notEqual(index, -1, 'Only an attached PRE may be replaced');
          body.slots[index] = { tagName: 'SVG', svg, source };
          onMutation();
        }
      });
      return pre;
    });
  }
  const initial = ['graph TD; A-->B;', 'sequenceDiagram; Alice->>Bob: Hello'];
  const replacement = ['graph TD; C-->D;', 'sequenceDiagram; Bob->>Alice: Reply'];
  body.slots = diagrams(initial);
  const context = {
    document: {
      readyState: 'complete', body,
      querySelectorAll(selector) {
        assert.equal(selector, '.language-mermaid');
        return body.slots.flatMap(pre => pre.tagName === 'PRE'
          ? [pre, pre.code].filter(node => node.classes.has('language-mermaid')) : []);
      }
    },
    window: { addEventListener: (event, callback) => { onLoad = callback; } },
    console: { warn() {}, error() {} },
    setTimeout: callback => { scheduled.push(callback); },
    MutationObserver: class {
      constructor(callback) { onMutation = callback; }
      observe(node, options) {
        assert.equal(node, body);
        assert.equal(options.childList, true);
        assert.equal(options.subtree, true);
      }
    },
    mermaid: {
      initialize() {},
      async render(id, source) {
        rendered.push(source);
        return { svg: '<svg>' + source + '</svg>' };
      }
    }
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,
    '../../MacDown/Resources/Extensions/mermaid.init.js'), 'utf8'), context);
  async function settle() {
    for (let i = 0; i < 10; i++) await Promise.resolve();
    while (scheduled.length) await scheduled.shift()();
  }
  await onLoad();
  await settle();
  assert.deepEqual(rendered, initial, 'PRE selection must not add renderer calls');
  assert.deepEqual(body.slots.map(node => node.source), initial);
  assert.equal(body.slots.filter(node => node.tagName === 'SVG').length, 2);
  body.slots = diagrams(replacement);
  onMutation();
  await settle();
  assert.deepEqual(rendered, initial.concat(replacement));
  assert.deepEqual(body.slots.map(node => node.source), replacement);
  assert.equal(body.slots.filter(node => node.tagName === 'SVG').length, 2);
  onMutation();
  await settle();
  assert.equal(rendered.length, 4, 'Completed SVG siblings must not render again');
  process.stdout.write('Mermaid R04 PRE/CODE siblings and body replacement: passed\n');
})().catch(error => { console.error(error); process.exitCode = 1; });
