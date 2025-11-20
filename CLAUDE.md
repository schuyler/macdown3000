# Claude Code Project Context

This document provides essential information for Claude Code when working on the MacDown 3000 project.

## Project Overview

**MacDown 3000** is an open source Markdown editor for macOS, released under the MIT License. It's built using Objective-C and Cocoa frameworks.

### Key Technologies
- **Language:** Objective-C
- **Platform:** macOS (10.14+)
- **Dependencies:** Hoedown (Markdown rendering), Prism (syntax highlighting), PEG Markdown Highlight (editor highlighting)
- **Build System:** Xcode, CocoaPods (managed via Bundler)

## GitHub API Access

**GitHub CLI (`gh`) Availability:**
- The `gh` CLI tool is **automatically installed** on Linux via SessionStart hook
- On macOS, `gh` is assumed to be pre-installed (via Homebrew)
- Location: `/tmp/gh/bin/gh` (Linux) or `gh` (macOS)
- The SessionStart hook (`.claude/scripts/install-gh.sh`) fetches the latest version from GitHub
- Alternatively, use `curl` with the GitHub REST API directly

### Repository Information
- **Repository:** https://github.com/schuyler/macdown3000

### Accessing the GitHub Token

**The GitHub token is NOT stored in the repository.** Instead, set it as an environment variable in your Claude Code environment.

#### Claude Code Web (Recommended)

Set the `GITHUB_TOKEN` environment variable in the Claude Code Web UI:

1. Go to Settings → Environment Configuration
2. Add environment variable: `GITHUB_TOKEN=your_github_pat_token_here`
3. The token will be available in all Claude Code Web sessions
4. Never committed to Git

See [Claude Code Web Environment Configuration](https://code.claude.com/docs/en/claude-code-on-the-web#environment-configuration) for details.

#### Claude Code CLI

For the CLI, set the environment variable before starting:

```bash
export GITHUB_TOKEN=your_github_pat_token_here
claude-code
```

Or add to your shell profile (~/.bashrc, ~/.zshrc, etc.).

#### Using GitHub CLI (`gh`)

The `gh` CLI is automatically installed and authenticated via the SessionStart hook.

**Automatic Authentication:**
The SessionStart hook automatically authenticates `gh` using the `GITHUB_TOKEN` environment variable. No manual authentication is needed in most cases.

**Manual Authentication (If Needed):**
If you need to manually authenticate in a new shell session:

```bash
# Secure method using printf (avoids token exposure in process listings)
printf "%s" "$GITHUB_TOKEN" | /tmp/gh/bin/gh auth login --with-token

# Check authentication status
GH_TOKEN="$GITHUB_TOKEN" /tmp/gh/bin/gh auth status
```

**Using gh Commands:**
```bash
# Once authenticated, use gh commands normally
/tmp/gh/bin/gh issue list --repo schuyler/macdown3000
/tmp/gh/bin/gh pr create --title "My PR" --body "Description"

# Or use GH_TOKEN for one-off commands (doesn't require auth login)
GH_TOKEN="$GITHUB_TOKEN" /tmp/gh/bin/gh issue list --repo schuyler/macdown3000
```

#### Token Rotation

When rotating your GitHub token:

1. Generate new token on GitHub
2. Update environment variable in Claude Code Web settings
3. Or update your shell profile if using CLI

### Common API Operations

#### Fetch an Issue
```bash
curl -H "Authorization: token $TOKEN" \
  https://api.github.com/repos/schuyler/macdown3000/issues/{number}
```

#### Post a Comment on an Issue
```bash
curl -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"body": "Your comment here"}' \
  https://api.github.com/repos/schuyler/macdown3000/issues/{number}/comments
```

#### Create a Pull Request
```bash
curl -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "PR title",
    "head": "branch-name",
    "base": "main",
    "body": "PR description"
  }' \
  https://api.github.com/repos/schuyler/macdown3000/pulls
```

#### Get Workflow Runs for a Branch
```bash
# URL-encode the branch name
ENCODED_BRANCH=$(python3 -c "import urllib.parse; print(urllib.parse.quote('branch-name'))")

# Get workflow runs
curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/schuyler/macdown3000/actions/runs?branch=${ENCODED_BRANCH}&event=push&per_page=1"
```

#### Get Workflow Run Status
```bash
curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/schuyler/macdown3000/actions/runs/{run_id}"
```

#### Get Job Logs (follows redirects)
```bash
# Get job ID from workflow run
curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/schuyler/macdown3000/actions/runs/{run_id}/jobs"

# Get logs (use -L to follow redirects)
curl -sL -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/schuyler/macdown3000/actions/jobs/{job_id}/logs"
```

## Testing

### Test Execution
- **Platform Requirement:** Tests can only run on macOS (this is a macOS application)
- **CI/CD:** GitHub Actions workflows run tests on macOS runners
- **Local Testing:** Tests require Xcode and macOS environment

### Workflow
1. Push code to trigger GitHub Actions
2. Monitor workflow status via GitHub API
3. Retrieve logs if tests fail
4. Iterate until tests pass

## Development Conventions

### Git Commit Messages
- **Co-authorship:** The project has `includeCoAuthoredBy: false` configured
- **DO NOT** add "Co-authored-by:" trailers to commits
- **DO NOT** mention co-authorship in PRs or commit messages

### Issue References
- Use "Related to #123" to reference issues
- **DO NOT** use "Fixes #123" or "Closes #123" (avoids auto-closing issues before manual verification)

### Branch Naming
- Feature branches should follow the pattern for Claude Code sessions
- Must start with `claude/` and end with the session ID
- Example: `claude/fix-rendering-bug-01Y4ommV4yZoApvin8ddozbw`

## Network Retry Policy

For git operations and GitHub API calls:
- Retry up to 4 times on network failures
- Use exponential backoff: 2s, 4s, 8s, 16s
- Example:
  ```bash
  # First attempt
  git push -u origin branch-name
  # If failed, wait 2s and retry
  # If failed again, wait 4s and retry
  # Continue with 8s, then 16s backoff
  ```

## Quick Reference Links

- **Repository:** https://github.com/schuyler/macdown3000
- **GitHub Actions:** https://github.com/schuyler/macdown3000/actions
- **GitHub API Docs:** https://docs.github.com/en/rest
