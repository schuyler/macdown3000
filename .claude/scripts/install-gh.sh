#!/bin/bash
#
# SessionStart script: GitHub CLI setup and token validation
# - Installs GitHub CLI on Linux with integrity verification
# - Validates GITHUB_TOKEN environment variable
# - Provides usage examples for GitHub API access
#
# Only runs on initial session startup (not resume/clear/compact)

# Read JSON input from stdin to check the source
INPUT=$(cat)
SOURCE=$(python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    source = data.get('source', 'unknown')
    # Validate source is one of expected values
    if source not in ['startup', 'resume', 'clear', 'compact', 'unknown']:
        print('unknown')
        sys.exit(1)
    print(source)
except (json.JSONDecodeError, KeyError):
    print('unknown')
    sys.exit(1)
" <<< "$INPUT")

# Only install on startup, skip silently on resume/clear/compact
if [ "$SOURCE" != "startup" ]; then
  exit 0
fi

echo "=== GitHub CLI and API Setup ==="
echo ""

OS=$(uname -s)

case "$OS" in
  Linux*)
    if [ ! -x /tmp/gh/bin/gh ]; then
      echo "📦 Installing latest GitHub CLI..."

      # Create secure temporary directory
      TEMP_DIR=$(mktemp -d /tmp/gh-install.XXXXXX)
      trap "rm -rf $TEMP_DIR" EXIT

      # Fetch latest release information from GitHub API
      RELEASE_JSON=$(curl -sS --fail --tlsv1.2 https://api.github.com/repos/cli/cli/releases/latest 2>/dev/null)

      if [ -z "$RELEASE_JSON" ]; then
        echo "⚠ Failed to fetch GitHub CLI release information"
        exit 1
      fi

      # Parse JSON properly to get download URL and version
      DOWNLOAD_INFO=$(echo "$RELEASE_JSON" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    version = data.get('tag_name', '')
    for asset in data.get('assets', []):
        name = asset.get('name', '')
        if 'linux_amd64.tar.gz' in name and not name.endswith('.sha256'):
            url = asset.get('browser_download_url', '')
            print(f'{version}|{url}')
            break
except (json.JSONDecodeError, KeyError) as e:
    sys.exit(1)
")

      if [ -z "$DOWNLOAD_INFO" ]; then
        echo "⚠ Failed to parse GitHub CLI release information"
        exit 1
      fi

      VERSION=$(echo "$DOWNLOAD_INFO" | cut -d'|' -f1)
      LATEST=$(echo "$DOWNLOAD_INFO" | cut -d'|' -f2)

      # Validate URL format and scheme
      if [[ ! "$LATEST" =~ ^https://github\.com/ ]]; then
        echo "⚠ Invalid download URL (must be from github.com): $LATEST"
        exit 1
      fi

      # Construct the expected filename for checksum verification
      TARBALL_NAME="gh_${VERSION#v}_linux_amd64.tar.gz"

      # Download tarball with proper filename
      echo "Downloading GitHub CLI $VERSION..."
      if ! curl -sS --fail --tlsv1.2 -L "$LATEST" -o "$TEMP_DIR/$TARBALL_NAME"; then
        echo "⚠ Failed to download GitHub CLI"
        exit 1
      fi

      # Download checksums file
      CHECKSUM_URL="https://github.com/cli/cli/releases/download/${VERSION}/gh_${VERSION#v}_checksums.txt"
      if ! curl -sS --fail --tlsv1.2 -L "$CHECKSUM_URL" -o "$TEMP_DIR/checksums.txt" 2>/dev/null; then
        echo "⚠ Warning: Could not download checksums file, skipping verification"
        echo "   Proceeding without checksum verification (not recommended)"
      else
        # Verify checksum
        echo "Verifying checksum..."
        cd "$TEMP_DIR"
        if ! sha256sum -c checksums.txt --ignore-missing 2>/dev/null | grep -q "OK"; then
          echo "⚠ Checksum verification failed - downloaded file may be corrupted or tampered"
          exit 1
        fi
        echo "✓ Checksum verified"
      fi

      # Extract to temp directory
      if ! tar -xzf "$TEMP_DIR/$TARBALL_NAME" -C "$TEMP_DIR"; then
        echo "⚠ Failed to extract GitHub CLI archive"
        exit 1
      fi

      # Find the extracted directory (should match pattern gh_VERSION_linux_amd64)
      EXTRACTED_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "gh_*_linux_amd64" | head -n1)

      if [ -z "$EXTRACTED_DIR" ]; then
        echo "⚠ Could not find extracted GitHub CLI directory"
        exit 1
      fi

      # Move to final location atomically
      if ! mv "$EXTRACTED_DIR" /tmp/gh; then
        echo "⚠ Failed to install GitHub CLI to /tmp/gh"
        exit 1
      fi

      if [ -x /tmp/gh/bin/gh ]; then
        echo "✓ GitHub CLI installed to /tmp/gh/bin/gh"
        /tmp/gh/bin/gh --version
      else
        echo "⚠ GitHub CLI installation failed"
        exit 1
      fi
    else
      echo "✓ GitHub CLI ready at /tmp/gh/bin/gh"
    fi
    ;;

  Darwin*)
    if command -v gh >/dev/null 2>&1; then
      echo "✓ GitHub CLI found: $(which gh)"
      gh --version
    else
      echo "⚠ GitHub CLI not found on macOS"
      echo "  Install with: brew install gh"
    fi
    ;;

  *)
    echo "⚠ Unknown OS: $OS - skipping GitHub CLI setup"
    ;;
esac

echo ""
echo "=== GitHub Token Configuration ==="
echo ""

# Check if GITHUB_TOKEN is set
if [ -z "$GITHUB_TOKEN" ]; then
  echo "❌ GITHUB_TOKEN environment variable is not set"
  echo ""
  echo "To enable GitHub API access:"
  echo ""
  echo "For Claude Code Web:"
  echo "  1. Go to Settings → Environment Configuration"
  echo "  2. Add environment variable: GITHUB_TOKEN=ghp_your_token_here"
  echo "  3. Restart session"
  echo ""
  echo "For Claude Code CLI:"
  echo "  export GITHUB_TOKEN=ghp_your_token_here"
  echo ""
  echo "Generate token at: https://github.com/settings/tokens"
  echo "Required scopes: repo, read:org, workflow"
  echo ""
else
  echo "✅ GITHUB_TOKEN is configured"
  echo ""

  # Authenticate gh CLI if available
  # Use GH_TOKEN which gh natively supports to avoid token exposure via echo
  if [ "$OS" = "Linux" ] && [ -x /tmp/gh/bin/gh ]; then
    echo "Authenticating gh CLI..."
    if GH_TOKEN="$GITHUB_TOKEN" /tmp/gh/bin/gh auth status >/dev/null 2>&1; then
      echo "✅ gh CLI authenticated"
    else
      # If not authenticated, login using secure method
      if printf "%s" "$GITHUB_TOKEN" | GH_TOKEN="$GITHUB_TOKEN" /tmp/gh/bin/gh auth login --with-token >/dev/null 2>&1; then
        echo "✅ gh CLI authenticated"
      else
        echo "⚠ gh CLI authentication failed"
      fi
    fi
  elif [ "$OS" = "Darwin" ] && command -v gh >/dev/null 2>&1; then
    echo "Authenticating gh CLI..."
    if GH_TOKEN="$GITHUB_TOKEN" gh auth status >/dev/null 2>&1; then
      echo "✅ gh CLI authenticated"
    else
      # If not authenticated, login using secure method
      if printf "%s" "$GITHUB_TOKEN" | GH_TOKEN="$GITHUB_TOKEN" gh auth login --with-token >/dev/null 2>&1; then
        echo "✅ gh CLI authenticated"
      else
        echo "⚠ gh CLI authentication failed"
      fi
    fi
  fi

  echo ""
  echo "GitHub CLI Usage (for macdown3000 repo):"
  echo "  /tmp/gh/bin/gh issue list --repo schuyler/macdown3000"
  echo "  /tmp/gh/bin/gh pr list --repo schuyler/macdown3000"
  echo "  /tmp/gh/bin/gh issue view 1 --repo schuyler/macdown3000"
  echo ""
  echo "GitHub API Usage (via curl):"
  echo "  # Use GH_TOKEN for gh CLI commands (preferred):"
  echo "  GH_TOKEN=\"\$GITHUB_TOKEN\" /tmp/gh/bin/gh issue list --repo schuyler/macdown3000"
  echo ""
  echo "  # For direct API calls with curl, token will be in process args:"
  echo '  curl -H "Authorization: token $GITHUB_TOKEN" \'
  echo "    https://api.github.com/repos/schuyler/macdown3000/issues"
  echo ""
fi
