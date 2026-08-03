# Claude Code Project Context

This document provides essential information for Claude Code when working on the MacDown 3000 project.

## Project Overview

**MacDown 3000** is an open source Markdown editor for macOS, released under the MIT License. It's built using Objective-C and Cocoa frameworks.

### Key Technologies
- **Language:** Objective-C
- **Platform:** macOS (10.14+)
- **Dependencies:** Hoedown (Markdown rendering), Prism (syntax highlighting), PEG Markdown Highlight (editor highlighting)
- **Build System:** Xcode, CocoaPods (managed via Bundler)

## GitHub access

GitHub operations run two ways depending on where the session is:

- **Locally** (e.g. macOS): use the `gh` CLI, pre-installed via Homebrew. It authenticates from your existing `gh` login or the `GH_TOKEN` environment variable — no `gh auth login` needed.
- **Claude Code on the web:** use the GitHub MCP tools, which are available automatically and need no `gh` install.

Workflow examples in `.claude/commands/` are written in `gh` form; when `gh` isn't on the PATH, use the equivalent GitHub MCP tool.

### Usage Examples (`gh`)

```bash
# Issues
gh issue list --repo schuyler/macdown3000
gh issue view 123 --repo schuyler/macdown3000
gh issue comment 123 --repo schuyler/macdown3000 --body "Comment text"

# Pull Requests
gh pr create --repo schuyler/macdown3000 --base main --title "Title" --body "Description"
gh pr list --repo schuyler/macdown3000

# Workflow Runs
gh run list --repo schuyler/macdown3000 --branch my-branch
gh run watch $RUN_ID --repo schuyler/macdown3000
gh run view $RUN_ID --repo schuyler/macdown3000 --log
```

### Repository
- **URL:** https://github.com/schuyler/macdown3000
- **Actions:** https://github.com/schuyler/macdown3000/actions

## Testing

- **Platform:** Tests only run on macOS (this is a macOS application)
- **CI/CD:** GitHub Actions runs tests on macOS runners
- **Local:** Requires Xcode and macOS

### Workflow
1. Push code to trigger GitHub Actions
2. Monitor with `gh run watch`
3. View logs with `gh run view --log`
4. Iterate until tests pass

## Development Conventions

### Git Commits
- **DO NOT** add "Co-authored-by:" trailers (`includeCoAuthoredBy: false`)
- Use "Related to #123" (not "Fixes #123" or "Closes #123")

### Branch Naming
- Must start with `claude/` and end with session ID
- Example: `claude/fix-rendering-bug-01Y4ommV4yZoApvin8ddozbw`

## The Rule of Two

This project's agent workflow is governed by the Rule of Two: no single agent both does work and blesses it. Every artifact has two different hands on it — one to produce it, one to review it.

- **Core principle.** Every piece of work an agent performs — no matter how small or mechanical it looks — must be reviewed and approved by a *different* agent before it proceeds. Work is *made* by a subagent and *reviewed* by a subagent, and the reviewer is never the same agent that produced the work.
- **The coordinator only orchestrates.** The top-level coordinating agent does not do the work itself and does not substitute its own judgment for a review. Its job is to dispatch subagents, route artifacts between them, and conserve its own context window so the workflow can run to completion. Subagents are the ones who read the code and docs and make the calls; the coordinator just orchestrates.
- **It applies to everything.** There are no exceptions and no "too trivial to review" carve-outs. The rule covers requirements interpretation, design, tests, implementation, documentation, CI fixes, merge/rebase conflict resolutions, and fixes made during self-review alike.
- **Two distinct review gates.** Design and implementation are reviewed separately, at two separate gates:
  - A **design-review gate**, before implementation begins.
  - An **implementation-review gate**, after implementation is done.
  
  Each gate passes only when its review turns up no blocker/critical or important issues.
- **Model tiers.** Implementation subagents may run on Sonnet. Design review and implementation review must be performed by Opus 4.8.
- **Mandatory re-review loop.** If a review returns any critical or important feedback, the work must be corrected and then sent back for another review. The coordinator may not unilaterally decide a fix is good enough and skip the re-review — re-review is mandatory even when the fix looks simple or purely mechanical, because a later review round can surface problems that were obscured by the issues found in an earlier round. Loop fix → re-review until a round comes back with no critical or important findings. Unreviewed work never proceeds.

## Network Retry Policy

For git and GitHub API calls:
- Retry up to 4 times on network failures
- Exponential backoff: 2s, 4s, 8s, 16s
