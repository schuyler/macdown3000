const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const script = fs.readFileSync('MacDown/Resources/updateHeaderLocations.js', 'utf8');
function element(tagName, nodes = []) {
    const node = {tagName, nodeType: 1, children: nodes.filter(x => x.nodeType === 1),
        firstChild: nodes[0] || null, getBoundingClientRect: () => ({top: 10}),
        compareDocumentPosition: () => 0};
    nodes.forEach((child, i) => {
        child.parentElement = node;
        child.nextSibling = nodes[i + 1] || null;
    });
    return node;
}
function text(value) { return {nodeType: 3, nodeValue: value}; }
function run(paragraph, image) {
    const state = {document: {body: {}, querySelectorAll: selector =>
        ({img: [image], p: [paragraph]}[selector] || [])}, window: {scrollY: 0},
        Node: {DOCUMENT_POSITION_FOLLOWING: 4, DOCUMENT_POSITION_PRECEDING: 2}};
    return Array.from(vm.runInNewContext(script, state).kinds);
}
let img = element('IMG');
assert.deepEqual(run(element('P', [text('before '), img]), img), [7]);
img = element('IMG');
assert.deepEqual(run(element('P', [text(' '), img, text('\n')]), img), [0]);
img = element('IMG');
let anchor = element('A', [img]);
assert.deepEqual(run(element('P', [text('before '), anchor]), img), [7]);
img = element('IMG');
anchor = element('A', [img]);
assert.deepEqual(run(element('P', [anchor]), img), [0]);
console.log('PASS standalone and inline image/link scroll reference classification');
