# GitHub Style Generator

This tool generates the GitHub-2020 style from GitHub's official Primer packages.
Application builds consume the committed stylesheet and require neither Node nor
the generator dependencies. Plain `make` verifies that this stylesheet exists.

To regenerate it deliberately, use Node.js 20.19 or newer and npm. Install the
locked dependencies, then review and commit the generated stylesheet:

```bash
npm ci --ignore-scripts --no-audit --no-fund
make regenerate
```

To update Primer itself, update the dependencies and lockfile before regenerating:

```bash
npm install
npm update @primer/css @primer/primitives
make regenerate
```

Primer's markdown rules reference design tokens such as `--base-size-16` and `--fgColor-default` without declaring them. `tokens.js` prepends a `:root` block declaring each token the rules use without a literal fallback, with values from `@primer/primitives` (sizes and the light color theme). Regeneration fails if the rules reference a token `@primer/primitives` doesn't define.

Regeneration replaces the output only after Sass and token resolution succeed.
The replacement remains readable by all users (mode `0644`); a failed generation
keeps the previous stylesheet. `make clean` only removes intermediate files.
