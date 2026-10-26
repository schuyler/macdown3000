// Prepends a :root block declaring the Primer tokens a compiled stylesheet
// needs. Primer's markdown rules reference tokens such as --base-size-16 and
// --fgColor-default but declare none of them; a var() with no declaration and
// no literal fallback invalidates its whole declaration.
//
// Usage: node tokens.js <primitives css>... < compiled.css > out.css
//
// Token values come from the first rule block of each primitives file; earlier
// files win. Exits non-zero if a var() chain without a literal fallback names
// no known token.

const fs = require('fs');

// Returns the declarations in the first {...} block of a CSS file.
function firstBlockTokens(path) {
  const css = fs.readFileSync(path, 'utf8');
  const open = css.indexOf('{');
  const close = css.indexOf('}', open);
  const tokens = new Map();
  const pattern = /(--[A-Za-z0-9_-]+)\s*:\s*([^;]+);/g;
  let match;
  while ((match = pattern.exec(css.slice(open + 1, close))) !== null) {
    tokens.set(match[1], match[2].trim());
  }
  return tokens;
}

// Parses the var() whose name starts at css[start] (just past "var(").
// Returns the names in its fallback chain, whether the chain ends in a
// literal, and the index just past its closing parenthesis.
function parseVar(css, start) {
  let i = start;
  while (i < css.length && css[i] !== ',' && css[i] !== ')') i++;
  const names = [css.slice(start, i).trim()];
  let literal = false;
  if (css[i] === ',') {
    i++;
    while (i < css.length && /\s/.test(css[i])) i++;
    if (css.startsWith('var(', i)) {
      const fallback = parseVar(css, i + 4);
      names.push(...fallback.names);
      literal = fallback.literal;
      i = fallback.end;
    } else if (css[i] !== ')') {
      literal = true;
    }
  }
  let depth = 0;
  while (i < css.length && (depth > 0 || css[i] !== ')')) {
    if (css[i] === '(') depth++;
    else if (css[i] === ')') depth--;
    i++;
  }
  return { names, literal, end: i + 1 };
}

// Returns the var() chains in css, outermost only.
function varChains(css) {
  const chains = [];
  let index = 0;
  for (;;) {
    const found = css.indexOf('var(', index);
    if (found === -1) return chains;
    const chain = parseVar(css, found + 4);
    chains.push(chain);
    index = chain.end;
  }
}

const tokens = new Map();
for (const path of process.argv.slice(2)) {
  for (const [name, value] of firstBlockTokens(path)) {
    if (!tokens.has(name)) tokens.set(name, value);
  }
}

const css = fs.readFileSync(0, 'utf8');
const needed = new Map();
const pending = varChains(css);
while (pending.length > 0) {
  const chain = pending.shift();
  if (chain.literal) continue;
  const name = chain.names.find((n) => tokens.has(n));
  if (name === undefined) {
    console.error(`tokens.js: no Primer token for var(${chain.names.join(', ')})`);
    process.exit(1);
  }
  if (needed.has(name)) continue;
  const value = tokens.get(name);
  needed.set(name, value);
  pending.push(...varChains(value));
}

const declarations = [...needed.keys()].sort()
  .map((name) => `  ${name}: ${needed.get(name)};\n`).join('');
process.stdout.write(`:root {\n${declarations}}\n\n${css}`);
