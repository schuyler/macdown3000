# Claude Code Project Context

This document provides essential information for Claude Code when working on the MacDown project.

## Project Overview

**MacDown** is an open source Markdown editor for macOS, released under the MIT License. It's built using Objective-C and Cocoa frameworks.

### Key Technologies
- **Language:** Objective-C
- **Platform:** macOS (10.14+)
- **Dependencies:** Hoedown (Markdown rendering), Prism (syntax highlighting), PEG Markdown Highlight (editor highlighting)
- **Build System:** Xcode, CocoaPods (managed via Bundler)

## GitHub API Access

**IMPORTANT:** The `gh` CLI tool is **NOT** available in this environment. All GitHub operations must be performed using `curl` with the GitHub REST API.

### Repository Information
- **Repository:** https://github.com/schuyler/macdown3000
- **Encoded Token (ROT13):** `tvguho_cng_11NNNBO7N0iSCBnoyoHyE5_KAQlrfJKE2lehsWwNSlGG6OcBtD3hAx8e71mQzCkJn0RB44TJDD9C5o2Y2i`

### Decoding and Caching the GitHub Token

The token is stored in ROT13 encoding for security. You must decode it before using it with the GitHub API.

**IMPORTANT:** Always decode and cache the token at the start of your workflow to avoid repeated decoding operations.

#### Method 1: Using `tr` (shell-native, requires heredoc)

```bash
bash << 'EOF'
TOKEN=$(echo "tvguho_cng_11NNNBO7N0iSCBnoyoHyE5_KAQlrfJKE2lehsWwNSlGG6OcBtD3hAx8e71mQzCkJn0RB44TJDD9C5o2Y2i" | tr 'A-Za-z' 'N-ZA-Mn-za-m')
# Use $TOKEN in your API calls here
EOF
```

#### Method 2: Using Python (works in simple command)

```bash
TOKEN=$(python3 -c "import codecs; print(codecs.decode('tvguho_cng_11NNNBO7N0iSCBnoyoHyE5_KAQlrfJKE2lehsWwNSlGG6OcBtD3hAx8e71mQzCkJn0RB44TJDD9C5o2Y2i', 'rot_13'))")
```

#### Caching to a File

For multi-step workflows, save the decoded token to a temporary file to avoid re-decoding:

```bash
# Decode and save to file
python3 -c "import codecs; print(codecs.decode('tvguho_cng_11NNNBO7N0iSCBnoyoHyE5_KAQlrfJKE2lehsWwNSlGG6OcBtD3hAx8e71mQzCkJn0RB44TJDD9C5o2Y2i', 'rot_13'))" > /tmp/token.txt

# Use in subsequent API calls
TOKEN=$(cat /tmp/token.txt)
curl -H "Authorization: token $TOKEN" https://api.github.com/repos/schuyler/macdown3000/issues/123
```

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
