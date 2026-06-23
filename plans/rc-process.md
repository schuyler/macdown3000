# MacDown Release Train & Reporter Validation

This document describes how MacDown 3000 batches unreleased work into **release
candidates (RCs)**, gets them validated by the people who reported the bugs, and
graduates validated work into final releases on a fixed cadence.

It complements two existing documents:

- `plans/release-process.md` — the signing/notarization/stapling pipeline (unchanged).
- `plans/release-checklist.md` — the manual steps to cut a final release (unchanged).

The mechanics of *building* an RC or a release are identical to today. What's new
here is **when** we cut, **who** validates, and **how** validated work graduates.

## Table of Contents

- [Why a train](#why-a-train)
- [The model in one paragraph](#the-model-in-one-paragraph)
- [Cadence](#cadence)
- [Versioning](#versioning)
- [Lifecycle of a change](#lifecycle-of-a-change)
- [Labels](#labels)
- [Release-day runbook](#release-day-runbook)
- [Reporter validation comments](#reporter-validation-comments)
- [The express lane (hotfixes)](#the-express-lane-hotfixes)
- [Edge cases](#edge-cases)
- [Bootstrapping the first cycle](#bootstrapping-the-first-cycle)

## Why a train

Manual release validation is the single biggest maintenance bottleneck. Between
v3000.0.6 and the time of writing, ~21 PRs merged to `main` over ~9 weeks — far
too much surface area for one person to hand-test in a sitting. The healthy
historical rhythm was a release every 6–11 days; the one long gap (Jan 25 →
Apr 7, 72 days) is exactly what happens when that validation burden piles up.

The fix is **not** to slow down. It's to move validation onto the people best
positioned to do it: the reporters who filed each bug and have the reproduction
case in hand. We ship them a signed build and let them confirm their own fix.

## The model in one paragraph

`main` is a single linear history. We do **not** cherry-pick individual fixes
into releases — the train leaves on schedule with everything currently aboard.
Reporter validation is a **green light / revert signal**, not a per-change gate:
everything in an RC graduates to the next release **unless** a reporter reports
it's still broken, in which case we revert that one commit before cutting the
release. Silence counts as acceptance. This keeps git history linear, avoids
cherry-pick conflicts, and gives every cycle a clean terminal state.

## Cadence

**Every other Sunday.** One recurring event per cycle that does two things back
to back:

1. **Promote** the previous RC → final release.
2. **Cut** the next RC from `main` HEAD.

Sunday is chosen deliberately for a solo maintainer: it's when the maintainer is
reliably at the keyboard with capacity (and credit headroom) to babysit the
agent-driven RC cut, contributor lookup, and notarization round-trip. The
usual "don't ship before the weekend" caution assumes a team that goes dark on
weekends; here the maintainer *is* the weekend coverage, and the 14-day
validation window means nothing is ever time-critical on release day.

Key intervals that fall out of a 2-week cadence:

| Property | Value |
|---|---|
| Validation window per RC | 14 days (cut Sunday → next release Sunday) |
| Typical batch size | ~5 changes per RC |
| Merge → ship latency | 2–4 weeks (≈2 if merged just before a cut, ≈4 if just after) |
| Release events per year | ~26 |

**Skip-if-empty:** if nothing meaningful merged since the last RC, the Sunday is
a no-op. A fixed calendar does not mean a mandatory redundant RC.

## Versioning

RCs are SemVer pre-releases of the *next* patch target; `release.yml` already
auto-detects the `-rc.N` suffix and marks the GitHub release as a pre-release.

- Latest stable is `v3000.0.6` → the in-flight target is **`3000.0.7`**.
- RCs for it are `v3000.0.7-rc.1`, `v3000.0.7-rc.2`, … each a **superset** of the
  previous RC (plus new merges, minus any reverts).
- On release day the validated train graduates to the final **`v3000.0.7`**, and
  the next RC opens as **`v3000.0.8-rc.1`**.

RCs are pre-releases and **must not** touch the stable pointer in `README.md`
(`**Version X.Y.Z** - Available Now`). Only a final release updates that line.

## Lifecycle of a change

```
merged to main
      │
      ▼
next RC cut (Sunday)  ──►  rc-pending label + validation comment to reporter(s)
      │
      ▼
14-day validation window
      │
      ├─ reporter confirms ............► rc-validated
      ├─ reporter silent ..............► stays rc-pending (silence = acceptance)
      └─ reporter says still broken ...► rc-broken → revert commit before release
      │
      ▼
release day (next Sunday)
      │
      ├─ rc-validated / rc-pending ....► graduates into the final release
      └─ rc-broken ....................► reverted; rides a future RC once re-fixed
```

A change merged at time *t* misses the RC cut just before it, first appears in
the *next* RC, validates for one cycle, and ships at the following release —
hence the 2–4 week latency.

## Labels

Validation state lives on the **issue** a change resolves (and/or the PR when
there's no linked issue). Three labels, created once:

| Label | Color | Meaning |
|---|---|---|
| `rc-pending` | `#fbca04` (yellow) | In the current RC, awaiting reporter validation |
| `rc-validated` | `#0e8a16` (green) | A reporter confirmed the fix against an RC build |
| `rc-broken` | `#d93f0b` (red) | A reporter reports it's still broken; revert before release |

Lifecycle: `rc-pending` is applied when a change **first** enters an RC. A
reporter's confirmation flips it to `rc-validated`; a "still broken" report flips
it to `rc-broken`. On graduation, the rc-* label is removed (the CHANGELOG and
release notes become the durable record). `rc-broken` items keep their label
until re-fixed and re-entered into a later RC.

These do not exist yet — create them before the first cycle:

```bash
gh label create rc-pending   --repo schuyler/macdown3000 --color fbca04 --description "In the current RC, awaiting reporter validation"
gh label create rc-validated --repo schuyler/macdown3000 --color 0e8a16 --description "Reporter confirmed the fix against an RC build"
gh label create rc-broken    --repo schuyler/macdown3000 --color d93f0b --description "Reporter reports still broken; revert before release"
```

## Release-day runbook

Every other Sunday, in order:

1. **Triage validation feedback.** Read the issues currently labelled
   `rc-pending`. Anyone who confirmed → `rc-validated`. Anyone reporting it's
   still broken → `rc-broken`.
2. **Handle `rc-broken`.** For each, `git revert` the offending commit(s) on
   `main` (or merge a quick re-fix if one is ready). Reverted work simply rides a
   future RC once re-fixed — it does not block the train.
3. **Graduate.** Run the existing **`/release`** workflow to cut the final
   `vX.Y.Z` from `main`. Its changelog/contributor step already produces the
   release notes; everything still aboard the train ships.
4. **Clear graduated labels.** Remove `rc-*` labels from issues included in the
   release (the CHANGELOG is now the record).
5. **Open the next RC.** Run **`/release-candidate`** to cut `vX.Y.(Z+1)-rc.1`
   from the new `main` HEAD, which tags + builds + staples the pre-release and
   posts validation comments to the new batch's reporters.

Steps 3 and 5 are the two builds; everything else is bookkeeping the
`/release-candidate` and `/release` skills automate.

## Reporter validation comments

When an RC is cut, each included change gets **one** comment on its linked
issue (or PR), tagging the reporter and any prior testers, with the RC download
link. Etiquette:

- **Comment once per change, on first inclusion in an RC.** A change that rides
  multiple RCs without feedback is **not** re-pinged each cycle — that's spam.
- Reuse the contributor lookup the `/release` skill already performs (it walks
  each PR's linked issues across both `schuyler/macdown3000` and
  `MacDownApp/macdown` to find reporters and testers).
- **Exclude @schuyler** from tags.
- Changes with no reporter (refactors, dependency bumps, maintainer features,
  infra) get `rc-pending` for tracking but **no comment** — there's no one to
  ask. They graduate on silence like anything else.

Suggested comment template:

```markdown
👋 A fix for this is available for testing in **MacDown {RC_VERSION}**.

If you have a moment, please download it, confirm the issue is resolved, and
reply here — your confirmation is what graduates the fix into the next stable
release (currently planned for {RELEASE_DATE}).

📦 Download: {RC_RELEASE_URL}

No rush — if we don't hear back, the fix ships anyway. Thanks for reporting it!
```

## The express lane (hotfixes)

Security and critical-severity fixes **do not wait for the train**. They ship
immediately off `main` as a normal patch release via the existing `/release`
workflow, outside the cycle. The CVE fixes in v3000.0.5 are the archetype. After
a hotfix, the next scheduled RC/release simply continues from the new `main`.

## Edge cases

- **Reporter never responds.** Intended behavior — silence graduates the change
  at the next release. Don't chase.
- **Reporter can't reproduce on demand** (intermittent bug). Treat as silence;
  it graduates. If it recurs post-release, it comes back as a new report.
- **An RC is found broadly broken** (not one fix, but the build itself). Fix
  forward on `main` and cut `-rc.(N+1)`; the validation window for the affected
  changes effectively resets to the new RC.
- **Empty cycle.** Skip the RC cut; still promote any prior RC that's due.
- **A change reported broken but the fix isn't ready by release day.** Revert it
  for this release; it re-enters a future RC once re-fixed. Never hold the whole
  train for one change.

## Bootstrapping the first cycle

There is no in-flight RC yet, so the first Sunday only does the **cut** half:

1. Create the three `rc-*` labels (commands above).
2. Run `/release-candidate` to cut `v3000.0.7-rc.1` from `main`, label the
   included issues `rc-pending`, and post validation comments.
3. Two Sundays later, the full runbook applies: graduate `v3000.0.7`, then cut
   `v3000.0.8-rc.1`.

---

**Last updated:** 2026-06-23
**Cadence:** every other Sunday · **Model:** release train, reporter validation
as green-light/revert signal
