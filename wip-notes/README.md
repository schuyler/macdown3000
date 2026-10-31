# Session working notes (not for merge)

Design docs (`*.md`, with approved requirements), the severity brief used in
every review (`SEVERITY.md`), and the scratch tooling from the session that
handled the v3000.0.9 bugs and issues #530/#653/#654/#655/#660.

- `l10n.py <Base xib>` / `l10n2.py`: compare each Base xib's titled controls
  with every localized table (missing / English-valued / stale keys).
- `gen653.py <repo> <outdir>`: write per-locale `<loc>.todo.json` of missing
  keys with English, context (menu path) and a glossary.
- `insert653.py <repo> <dir>`: insert `<loc>.done.json` translations in ibtool
  format, resolve submenu `same_as` titles, copy uk tables to ru-RU.
- `l10n653/`: the todo/done JSON and the translator/reviewer briefs.
- `waitci.sh <sha>` / `waitrun.sh <branch>`: poll GitHub's public API for CI.

Delete this branch once #530, #653 and #654 are merged.
