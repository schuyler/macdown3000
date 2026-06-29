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
- [Release branch conventions](#release-branch-conventions)
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

Development happens on `main`. When an RC is cut, a short-lived **release
branch** (`release/X.Y.Z`) is created from `main` HEAD. The RC is tagged from
that branch, and `main` stays open for new work. Reporter validation is a
**green light / revert signal**: everything in the RC graduates **unless** a
reporter reports it's still broken, in which case that commit is reverted on the
release branch. Silence counts as acceptance. On release day, the final release
is tagged from the release branch, the graduation commit (changelog + README
update) is cherry-picked onto `main`, and the branch is deleted — the release
tag keeps the branch's commits reachable permanently. Changes flow one way: from
`main` into the release branch at cut time, never back. Then the next RC is cut
from the new `main` HEAD.

## Cadence

**Every other Sunday.** One recurring event per cycle that does two things back
to back:

1. **Graduate** the previous RC → final release (from its release branch).
2. **Cut** the next RC from `main` HEAD (creates a new release branch).

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

### Changelog handling

`release.yml` and `staple-release.yml` both gate on a `## [${VERSION}]` section
in `CHANGELOG.md` matching the tag exactly — `-rc.N` and all — and extract its
body as the release notes. So an RC needs a section, but we don't want RC noise
polluting the permanent changelog. The compromise:

- The rolling `## [Unreleased]` section on `main` is the single accumulator and
  is **never** destroyed by an RC cut — PR entries keep landing there as normal.
- `/release-candidate` inserts a **temporary snapshot** section on the **release
  branch**, fenced by `<!-- rc-temp -->` / `<!-- /rc-temp -->`, containing the
  generated changelog under the RC's version+date heading. This satisfies the CI
  gate and gives the RC sensible release notes. Because this happens on the
  release branch, `main`'s CHANGELOG is untouched.
- At graduation, `/release` works on the **release branch**: strips the
  `rc-temp` block, writes the final `## [X.Y.Z]` section (regenerated from the
  commit range, reflecting any reverts), and updates `README.md`. The release is
  tagged from this commit. The graduation commit is then cherry-picked onto
  `main` so that `main`'s CHANGELOG carries the full release history. The release
  branch is deleted afterward — the release tag keeps its commits reachable.

## Lifecycle of a change

```
merged to main
      │
      ▼
RC cut Sunday
      ├─ create release/X.Y.Z from main HEAD
      ├─ tag RC from release branch
      └─ rc-pending label + validation comment to reporter(s)
      │
      ▼
14-day validation window (main stays open for new work)
      │
      ├─ reporter confirms ............► rc-validated
      ├─ reporter silent ..............► stays rc-pending (silence = acceptance)
      └─ reporter says still broken ...► rc-broken → revert on release branch
      │
      ▼
release day (next Sunday)
      ├─ tag final release from release branch
      ├─ cherry-pick graduation commit (changelog + README) onto main
      ├─ delete release branch
      └─ cut next RC from main HEAD (new release branch)
      │
      ├─ rc-validated / rc-pending ....► graduates into the final release
      └─ rc-broken ....................► reverted on branch; re-fixed work rides a future RC
```

A change merged at time *t* misses the RC cut just before it, first appears in
the *next* RC, validates for one cycle, and ships at the following release —
hence the 2–4 week latency. Meanwhile, `main` never stops — new work merges
continuously and rides the *next* release branch.

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
it to `rc-broken`. On graduation, `rc-pending` and `rc-validated` labels are
removed from issues whose changes **shipped** (the CHANGELOG becomes the durable
record). `rc-broken` labels are **not** removed at graduation — the change
didn't ship. They stay until the fix author addresses the issue on `main` and
the change re-enters a later RC as `rc-pending`.

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
2. **Handle `rc-broken`.** Check out the release branch (`release/X.Y.Z`). For
   each broken change, `git revert` the offending commit(s) on the release
   branch (or apply a quick fix if one is ready). Reverted work rides a future
   RC once re-fixed — it does not block the train. **Do not** revert on `main`;
   the release branch is isolated specifically so `main` isn't affected by
   release-time surgery. (Note: because reverts stay on the branch, the broken
   code remains on `main`. It will reappear in the next RC unless the fix author
   commits a fix to `main` before the next RC cut. This is intentional — `main`
   does not need to be in a releasable state; the release branch is what ships.)
3. **Graduate.** Run **`/release`** against the release branch. It strips the
   `rc-temp` changelog block, generates the final `## [X.Y.Z]` entry (from the
   commit range on the branch, reflecting any reverts), updates `README.md`,
   tags the final release from the branch, cherry-picks the graduation commit
   onto `main`, and deletes the release branch. Everything still aboard the
   branch ships.
4. **Clear graduated labels.** Remove `rc-pending` and `rc-validated` labels
   from issues whose changes shipped in this release. **Do not** remove
   `rc-broken` — those changes didn't ship and the label should stay until the
   fix is re-merged and re-enters a future RC.
5. **Open the next RC.** Switch to `main`, then run **`/release-candidate`** to
   cut `vX.Y.(Z+1)-rc.1` from the new `main` HEAD. This creates a fresh `release/X.Y.(Z+1)` branch,
   tags + builds + staples the pre-release, and posts validation comments to the
   new batch's reporters.

Steps 3 and 5 are the two builds; everything else is bookkeeping the
`/release-candidate` and `/release` skills automate.

## Reporter validation comments

When an RC is cut, each included change gets **one** comment on its linked
issue (or PR), tagging the reporter and any prior testers, with the RC download
link. Etiquette:

- **Comment once per change, on first inclusion in an RC.** A change that rides
  multiple RCs without feedback is **not** re-pinged each cycle — that's spam.
  The skill enforces this idempotently by checking the issue for a prior
  `<!-- rc-validation-ping -->` marker before posting, so it's safe across
  ephemeral sessions that don't remember last cycle.
- Reuse the contributor lookup the `/release` skill already performs to *find*
  reporters and testers (it walks linked issues across both `schuyler/macdown3000`
  and `MacDownApp/macdown`). **But only `@`-mention people who engaged on
  `schuyler/macdown3000`.** Cross-repo lookup is fine for *crediting* in a
  changelog; actively pinging someone who filed a bug on the upstream
  `MacDownApp/macdown` years ago and never opted into this fork is not.
- **Exclude @schuyler** from tags.
- Changes with no reporter (refactors, dependency bumps, maintainer features,
  infra) get `rc-pending` for tracking but **no comment** — there's no one to
  ask. They graduate on silence like anything else.

Suggested comment template (the hidden marker makes the ping idempotent; the
Gatekeeper note keeps a non-technical reporter from misreading a first-launch
quarantine prompt as the bug being unfixed):

```markdown
<!-- rc-validation-ping -->
👋 A fix for this is available for testing in **MacDown {RC_VERSION}**.

If you have a moment, please download it, confirm the issue is resolved, and
reply here — your confirmation is what graduates the fix into the next stable
release (currently planned for {RELEASE_DATE}).

📦 Download: {RC_RELEASE_URL}

> First launch: if macOS says the app is from an unidentified developer,
> right-click the app and choose **Open**, then confirm. (Signed, notarized
> pre-release build.)

No rush — if we don't hear back, the fix ships anyway. Thanks for reporting it!
```

## The express lane (hotfixes)

Security and critical-severity fixes **do not wait for the train**. They ship
immediately off `main` via **`/hotfix`** — a separate skill that tags and
releases directly from `main`, outside the release branch model. The CVE fixes
in v3000.0.5 are the archetype.

If an RC's release branch already exists when a hotfix ships from `main`, the
hotfix commit should be cherry-picked onto the release branch so the next
graduation includes it. (The final release should never be *behind* the latest
hotfix.) After a hotfix, the next scheduled RC/release continues from the new
`main`.

Three skills, one job each:

| Skill | Operates on | Purpose |
|---|---|---|
| `/release-candidate` | `main` → new `release/X.Y.Z` | Cut an RC, create the release branch |
| `/release` | `release/X.Y.Z` | Graduate an RC to a final release |
| `/hotfix` | `main` | Ship a critical fix immediately, outside the train |

## Edge cases

- **Reporter never responds.** Intended behavior — silence graduates the change
  at the next release. Don't chase.
- **Reporter can't reproduce on demand** (intermittent bug). Treat as silence;
  it graduates. If it recurs post-release, it comes back as a new report.
- **An RC is found broadly broken** (not one fix, but the build itself). Fix on
  the release branch and cut `-rc.(N+1)` from it; the validation window for the
  affected changes effectively resets to the new RC.
- **Empty cycle.** Skip the RC cut; still promote any prior RC that's due.
- **A change reported broken but the fix isn't ready by release day.** Revert it
  on the release branch; it re-enters a future RC once re-fixed on `main`. Never
  hold the whole train for one change.
- **The broken commit has dependent work built on top of it.** A clean isolated
  `git revert` may not exist (it'll conflict, or silently undo the dependent
  change too). Don't force it — prefer a forward-fix on the release branch, or
  hold this one change by cutting a fresh `-rc.(N+1)` and letting it graduate a
  cycle later.
- **Hotfix ships while a release branch exists.** Cherry-pick the hotfix onto
  the release branch. The graduated release must never be behind the latest
  stable.
- **Cherry-pick conflict on graduation.** The graduation commit (changelog +
  README) is cherry-picked onto `main`. If `main`'s CHANGELOG has changed since
  the branch point (e.g. new `[Unreleased]` entries), the cherry-pick may
  conflict. Resolve by keeping both: `main`'s `[Unreleased]` entries and the new
  release section.
- **Release day skipped** (maintainer unavailable). The release branch stays
  open. Graduate on the next available Sunday; the validation window simply
  extends. The next RC cut follows immediately after.

## Release branch conventions

- **Name:** `release/X.Y.Z` (e.g. `release/3000.0.7`). One branch per release
  target; RC iterations (`-rc.1`, `-rc.2`) are tags on the same branch.
- **Created by:** `/release-candidate` when cutting the first RC for a target.
- **Lives for:** one validation cycle (14 days), then deleted after graduation.
- **Commits allowed:** changelog/README updates, reverts of `rc-broken` changes,
  forward-fixes for broken changes, cherry-picked hotfixes. No new feature work.
- **Flow is one-way:** changes flow from `main` into the release branch at cut
  time. Nothing flows back. The graduation commit (changelog + README) is
  cherry-picked onto `main`; reverts and forward-fixes on the branch stay there.
- **Deletion:** after tagging the final release and cherry-picking the graduation
  commit, delete the branch. The release tag keeps all commits reachable.

## Bootstrapping the first cycle

Before the first cycle, these one-time prerequisites must be completed:

1. Create the three `rc-*` labels (commands above).
2. **Update `release.yml`**: the workflow currently enforces that tags are
   ancestors of `origin/main` (`git merge-base --is-ancestor`). Under the
   release branch model, RC and release tags are created on `release/*` branches.
   The ancestry check must be relaxed to also accept tags on `release/*` branches,
   or removed entirely (the branch naming convention provides sufficient
   protection against accidental dev-branch tags).
3. **Update `/release-candidate`** and **`/release`** skills to implement the
   release branch model (create/operate on `release/X.Y.Z` instead of `main`).
4. **Create `/hotfix`** skill for express-lane releases from `main`.

Then the first Sunday only does the **cut** half:

1. Run `/release-candidate` to cut `v3000.0.7-rc.1` from `main` — this creates
   the `release/3000.0.7` branch, tags the RC from it, and posts validation
   comments.
2. Two Sundays later, the full runbook applies: graduate `v3000.0.7` from the
   release branch, cherry-pick the graduation commit to `main`, delete the
   branch, then cut `v3000.0.8-rc.1` (creating `release/3000.0.8`).

---

**Last updated:** 2026-06-29
**Cadence:** every other Sunday · **Model:** release train, reporter validation
as green-light/revert signal
