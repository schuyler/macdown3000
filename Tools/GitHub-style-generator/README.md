# GitHub Style Generator

Generates the MacDown GitHub stylesheet from the pinned `@primer/css` package.
Primitive dimensions, light color tokens and base styles are included so the
standalone HTML template resolves the Markdown stylesheet’s CSS variables.
The template selects the light theme with `data-color-mode` and
`data-light-theme` attributes.

Node.js 20.19 or newer and npm are required by the pinned Sass compiler.

From this directory:

```sh
npm ci --ignore-scripts --no-audit --no-fund
make
```

The repository `setup.sh` installs these dependencies as well. Xcode runs the
generator once in the shared resources target before the app and Quick Look
consume its output. Failed Sass compilation preserves the existing stylesheet
and stops the build.

To update the upstream style deliberately, change dependencies in `package.json`,
run `npm install` to update `package-lock.json`, then regenerate and review the CSS.
