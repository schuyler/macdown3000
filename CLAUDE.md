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

## Network Retry Policy

For git and GitHub API calls:
- Retry up to 4 times on network failures
- Exponential backoff: 2s, 4s, 8s, 16s
