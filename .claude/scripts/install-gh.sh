#!/bin/bash
#
# GitHub CLI installer for Claude Code Web.
#
# - Installs GitHub CLI on Linux (assumes brew on macOS)
# - Validates GH_TOKEN is set
#
# gh automatically uses GH_TOKEN - no auth login needed.
#

# Check dependencies
check_dependency() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "✗ Required dependency not found: $1"
        return 1
    fi
    return 0
}

echo "=== GitHub CLI Setup ==="
echo ""

OS=$(uname -s)

case "$OS" in
    Linux*)
        if [ -x /tmp/gh/bin/gh ]; then
            echo "✓ GitHub CLI ready at /tmp/gh/bin/gh"
        else
            # Check dependencies
            check_dependency curl || exit 1
            check_dependency jq || exit 1

            echo "📦 Installing GitHub CLI..."

            # Detect architecture
            ARCH=$(uname -m)
            case "$ARCH" in
                x86_64)  GH_ARCH="amd64" ;;
                aarch64) GH_ARCH="arm64" ;;
                armv7l)  GH_ARCH="armv6" ;;
                *)
                    echo "✗ Unsupported architecture: $ARCH"
                    exit 1
                    ;;
            esac

            TEMP_DIR=$(mktemp -d)
            trap "rm -rf $TEMP_DIR" EXIT

            # Fetch latest release info
            RELEASE_JSON=$(curl -sS --fail --connect-timeout 10 --max-time 30 \
                https://api.github.com/repos/cli/cli/releases/latest 2>/dev/null)

            if [ -z "$RELEASE_JSON" ]; then
                echo "✗ Failed to fetch release info"
                exit 1
            fi

            # Parse version and download URL
            VERSION=$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty')
            if [ -z "$VERSION" ]; then
                echo "✗ Failed to parse version"
                exit 1
            fi

            URL=$(echo "$RELEASE_JSON" | jq -r --arg arch "$GH_ARCH" '
                .assets[] |
                select(.name | test("linux_" + $arch + ".tar.gz$")) |
                .browser_download_url
            ')

            if [ -z "$URL" ]; then
                echo "✗ No download available for linux_$GH_ARCH"
                exit 1
            fi

            # Download tarball
            VERSION_NUM="${VERSION#v}"
            TARBALL="gh_${VERSION_NUM}_linux_${GH_ARCH}.tar.gz"
            EXTRACT_DIR="gh_${VERSION_NUM}_linux_${GH_ARCH}"

            echo "  Downloading $VERSION for $GH_ARCH..."
            if ! curl -sS --fail --connect-timeout 10 --max-time 120 -L "$URL" -o "$TEMP_DIR/$TARBALL"; then
                echo "✗ Download failed"
                exit 1
            fi

            # Download and verify checksum
            CHECKSUM_URL="https://github.com/cli/cli/releases/download/${VERSION}/gh_${VERSION_NUM}_checksums.txt"
            if curl -sS --fail --connect-timeout 10 --max-time 30 -L "$CHECKSUM_URL" -o "$TEMP_DIR/checksums.txt" 2>/dev/null; then
                echo "  Verifying checksum..."
                if ! (cd "$TEMP_DIR" && grep "$TARBALL" checksums.txt | sha256sum -c --quiet 2>/dev/null); then
                    echo "✗ Checksum verification failed"
                    exit 1
                fi
            else
                echo "⚠ Could not download checksums, skipping verification"
            fi

            # Extract
            if ! tar -xzf "$TEMP_DIR/$TARBALL" -C "$TEMP_DIR"; then
                echo "✗ Extract failed"
                exit 1
            fi

            # Install (atomic move)
            if [ ! -d "$TEMP_DIR/$EXTRACT_DIR" ]; then
                echo "✗ Expected directory not found: $EXTRACT_DIR"
                exit 1
            fi

            if ! mv "$TEMP_DIR/$EXTRACT_DIR" /tmp/gh; then
                echo "✗ Install failed"
                exit 1
            fi

            # Verify installation
            if ! /tmp/gh/bin/gh --version >/dev/null 2>&1; then
                echo "✗ Installation verification failed"
                rm -rf /tmp/gh
                exit 1
            fi

            echo "  ✓ Installed $(/tmp/gh/bin/gh --version | head -1)"
        fi
        ;;

    Darwin*)
        if command -v gh >/dev/null 2>&1; then
            echo "✓ GitHub CLI found: $(gh --version | head -1)"
        else
            echo "⚠ GitHub CLI not found. Install with: brew install gh"
        fi
        ;;

    *)
        echo "⚠ Unknown OS: $OS"
        ;;
esac

echo ""

# Check for token
if [ -n "$GH_TOKEN" ]; then
    echo "✓ GH_TOKEN is set"
else
    echo "⚠ GH_TOKEN not set"
    echo ""
    echo "Set GH_TOKEN in Claude Code Web:"
    echo "  Settings → Environment Configuration → Add GH_TOKEN"
    echo ""
    echo "Generate token at: https://github.com/settings/tokens"
    echo "Required scopes: repo, read:org"
fi
