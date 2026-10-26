# GitHub Style Generator

This tool generates the GitHub-2020 style from GitHub's official Primer packages. npm 5 or above is required (to make use of `package-lock.json`). To update the style, run:

```bash
npm install
npm update @primer/css @primer/primitives
make -B
```

Primer's markdown rules reference design tokens such as `--base-size-16` and `--fgColor-default` without declaring them. `tokens.js` prepends a `:root` block declaring each token the rules use without a literal fallback, with values from `@primer/primitives` (sizes and the light color theme). `make` fails if the rules reference a token `@primer/primitives` doesn't define.
