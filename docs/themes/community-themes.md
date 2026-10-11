# Community themes

MacDown bundles all 37 coordinated palettes from
[mfeilen/macdown3000-themes](https://github.com/mfeilen/macdown3000-themes),
pinned to commit `20a444e37182cf75e3f021ac5811ce7ceec59049`.
The upstream Prism CSS snapshot is `PrismJS/prism-themes` commit `447479f`.

Choose a palette in **Settings → Editor → Theme**, its matching preview CSS in
**Settings → Rendering**, and the corresponding code highlighting theme.
The `+` editor variant also changes heading sizes. The three settings remain
independent; importing these themes does not change existing preferences.
The table below maps the readable palette name to its highlighting filename;
MacDown derives the highlighting menu title by removing `prism-` and `.css`
and capitalizing the filename.

The files use the existing bundle resource lookup. User files with the same
names continue to override bundled resources. Nothing is installed into or
removed from Application Support. The upstream installer and converter are
not shipped or executed. Both application and Quick Look build resources
consume the same tracked Prism overlay.

## Local change and review

Hopscotch's Google Fonts `@import` was removed. Its installed-font fallback
remains intact, so using the theme makes no font network request. Pojoaque's
original background texture remains a small embedded JPEG. The other theme
assets are byte-identical to the pinned source. Original author comments and
license notices are preserved. `COMMUNITY-THEMES-LICENSE.txt` accompanies the
assets in the bundle; the editor/preview conversion is MIT, the Prism
collection carries its upstream MIT license, and Hopscotch retains its CC0
notice. See [individual author credits](community-credits.md).

The manifest records every theme asset's SHA-256, all 37 palette mappings,
and the one local modification. The contract test verifies asset integrity,
absence of remote CSS resources and active CSS expressions, and parses all
74 editor variants through the actual PEG style parser. It also accepts a
built application's Resources directory to verify packaging.

These are optional artistic palettes. They have different contrast levels;
this integration does not certify every token as WCAG accessible. Select a
palette appropriate to your needs. No automated color correction changes the
original palette. Print rendering continues to use MacDown's print settings.

## Palettes

| Editor / preview palette | Code highlighting filename |
| --- | --- |
| Atelier Sulphurpool Light | `prism-base16-ateliersulphurpool.light.css` |
| Atom Dark | `prism-atom-dark.css` |
| CB | `prism-cb.css` |
| Coldark Cold | `prism-coldark-cold.css` |
| Coldark Dark | `prism-coldark-dark.css` |
| Coy without shadows | `prism-coy-without-shadows.css` |
| Darcula | `prism-darcula.css` |
| Dracula | `prism-dracula.css` |
| Duotone Dark | `prism-duotone-dark.css` |
| Duotone Earth | `prism-duotone-earth.css` |
| Duotone Forest | `prism-duotone-forest.css` |
| Duotone Light | `prism-duotone-light.css` |
| Duotone Sea | `prism-duotone-sea.css` |
| Duotone Space | `prism-duotone-space.css` |
| GHColors | `prism-ghcolors.css` |
| Gruvbox Dark | `prism-gruvbox-dark.css` |
| Gruvbox Light | `prism-gruvbox-light.css` |
| Holi Theme | `prism-holi-theme.css` |
| Hopscotch | `prism-hopscotch.css` |
| Laserwave | `prism-laserwave.css` |
| Lucario | `prism-lucario.css` |
| Material Dark | `prism-material-dark.css` |
| Material Light | `prism-material-light.css` |
| Material Oceanic | `prism-material-oceanic.css` |
| Night Owl | `prism-night-owl.css` |
| Nord | `prism-nord.css` |
| One Dark | `prism-one-dark.css` |
| One Light | `prism-one-light.css` |
| Pojoaque | `prism-pojoaque.css` |
| Shades of Purple | `prism-shades-of-purple.css` |
| Solarized Dark Atom | `prism-solarized-dark-atom.css` |
| Synthwave 84 | `prism-synthwave84.css` |
| VS Code Dark Plus | `prism-vsc-dark-plus.css` |
| VS | `prism-vs.css` |
| Xonokai | `prism-xonokai.css` |
| Z-Touch | `prism-z-touch.css` |
| a11y Dark | `prism-a11y-dark.css` |
