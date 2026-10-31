# Translation review brief (issue #653, MacDown 3000 — a macOS Markdown editor)

You are a cold, READ-ONLY reviewer (modify nothing) holding the translation-quality part of the implementation gate.
For each locale assigned to you, in /tmp/claude-0/-home-user-macdown3000/69b3fd22-dc82-5c34-908d-db011c91fb5f/scratchpad/l10n653/:
- `<locale>.todo.json` → `missing`: "<Table>::<key>" -> {english, class, context}; `glossary`: the locale's existing app translations.
- `<locale>.done.json` → the new translations (entries with `same_as` in todo were skipped; they copy the parent menu item's translation automatically).
The translator brief is BRIEF.md in the same directory.

Check every translation as a fluent reviewer of that language:
- important: a translation whose meaning is WRONG or misleading for the control (it would make the UI say something else), a non-target-language/mixed-script string, a string left in English that isn't a product name / H1–H6 / symbol, broken placeholders or ellipsis-escaping problems, or a translation that contradicts an identical English term already translated in the glossary in a way that would show two different words for the same command in the same menu.
- cosmetic: awkward but correct wording, alternative macOS terminology, style.
Severity definitions (verbatim): critical — it is broken. important — it doesn't meet requirements, or it changes tests to mask a bug, or it leaves behind a test that can't fail if the code it covers changed. cosmetic — everything else; cosmetic findings never fail a gate. A finding reaches critical or important only if it names a specific scenario: here, the exact key, the current translation, why its meaning is wrong, and a corrected translation.
Return: per locale PASS/FAIL; for every important finding: locale, key, English, current, proposed. Keep cosmetic notes brief (at most 5 per locale). Under 700 words total.
