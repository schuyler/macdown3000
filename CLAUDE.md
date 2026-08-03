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

This project's agent workflow is governed by the Rule of Two: no change reaches `main` without a different agent reviewing it. The coordinator may do work itself or dispatch subagents for it — that part is flexible. What is non-negotiable is that a subagent review happens before anything is committed or pushed.

- **Core principle.** No change — no matter how small, mechanical, or explicitly specified by the user — may be committed or pushed until a subagent that did not make the change has reviewed and approved the current state of the branch.
- **Two distinct review gates.** Design and implementation are reviewed separately, at two separate gates: a **design-review gate**, before implementation begins, and an **implementation-review gate**, after implementation is done. Each gate passes only when its review turns up no blocker/critical or important issues.
- **Reviews must be performed by Opus subagents.**
- **Full-branch re-review, always.** Any change — including a fix made to address a review finding — invalidates prior approval. The next review must cover the entire diff from `main`, not just the newest edits. Reviewing only the latest batch of changes lets small "obviously fine" fixes accumulate unreviewed; this is not allowed.
- **Mandatory re-review loop.** Critical or important feedback requires a fix followed by a fresh full-branch review. No unilaterally deciding a fix is good enough to skip re-review, no matter how simple or mechanical it looks.
- **Watch for the rationalization.** The rule most often breaks when an agent decides a change is "trivial" or "just what the user asked for" and skips review on that basis. That is exactly when review is most likely to be skipped, and most needed.
- **Operational check.** If you're about to commit or push without a review subagent having approved the current state of the branch, stop. That's the signal you skipped a step.

## Network Retry Policy

For git and GitHub API calls:
- Retry up to 4 times on network failures
- Exponential backoff: 2s, 4s, 8s, 16s
