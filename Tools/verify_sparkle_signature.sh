#!/bin/bash
#
# Verify the embedded Sparkle.framework carries signatures Apple will notarize.
#
# codesign --deep --strict checks structural validity, not the signer identity
# of nested code, so it passes on ad-hoc nested components. This checks the four
# properties notarization actually rejects on, before a notarization round trip
# is spent learning them.
#
# Read-only: makes no signing calls, so it works against a read-only DMG mount.
#
# Usage: bash Tools/verify_sparkle_signature.sh <path-to-app-bundle> <team-id>

set -o errexit
set -o nounset
set -o pipefail

APP_ARG="${1:-}"
TEAM_ID="${2:-}"

if [ -z "$APP_ARG" ] || [ -z "$TEAM_ID" ]; then
    echo "::error::usage: verify_sparkle_signature.sh <path-to-app-bundle> <team-id>" >&2
    exit 1
fi

if [ ! -d "$APP_ARG" ]; then
    echo "::error::app bundle not found at: $APP_ARG" >&2
    exit 1
fi

APP=$(cd "$APP_ARG" && pwd -P)
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"

if [ ! -d "$FRAMEWORK" ]; then
    echo "::error::Sparkle.framework not found at: $FRAMEWORK" >&2
    exit 1
fi

if [ ! -d "$FRAMEWORK/Versions/Current" ]; then
    echo "::error::$FRAMEWORK has no Versions/Current" >&2
    exit 1
fi
VERSION_DIR=$(cd "$FRAMEWORK/Versions/Current" && pwd -P)

# Keep in sync with Tools/sign_sparkle.sh.
COMPONENTS=(
    "$VERSION_DIR/XPCServices/Downloader.xpc"
    "$VERSION_DIR/XPCServices/Installer.xpc"
    "$VERSION_DIR/Updater.app"
    "$VERSION_DIR/Autoupdate"
    "$FRAMEWORK"
)
EXPECTED_MACHO_COUNT=5

FAILED=0

fail() {
    echo "::error::$1" >&2
    FAILED=1
}

echo "🔍 Verifying Sparkle component signatures in $APP..."

# An added component would be sealed unsigned by the framework's signature
# rather than re-signed, so count before trusting the list. `file` reports a
# universal binary on several lines -- one summary plus one per architecture --
# so per-architecture lines are dropped to count files, not slices.
MACHO_COUNT=$(find "$VERSION_DIR" -type f -exec file {} + \
    | grep -v "(for architecture" \
    | grep -c "Mach-O" || true)
if [ "$MACHO_COUNT" -ne "$EXPECTED_MACHO_COUNT" ]; then
    fail "expected $EXPECTED_MACHO_COUNT Mach-O binaries under $VERSION_DIR, found $MACHO_COUNT"
    echo "::error::Sparkle's layout changed; update COMPONENTS in Tools/sign_sparkle.sh and Tools/verify_sparkle_signature.sh" >&2
fi

for component in "${COMPONENTS[@]}"; do
    name=$(basename "$component")

    if [ ! -e "$component" ]; then
        fail "$name: expected Sparkle component is missing at $component"
        continue
    fi

    if ! codesign --verify --strict "$component" >/dev/null 2>&1; then
        fail "$name: code signature is not valid"
    fi

    # codesign -dvv writes to stderr; `|| true` keeps set -e from aborting here.
    info=$(codesign -dvv "$component" 2>&1 || true)

    case "$info" in
        *"Authority=Developer ID Application"*) ;;
        *) fail "$name: not signed with a Developer ID Application certificate" ;;
    esac

    flags=$(printf '%s\n' "$info" | sed -n 's/.*\(flags=0x[0-9a-f]*([^)]*)\).*/\1/p' | head -1)
    case "$flags" in
        *runtime*) ;;
        *) fail "$name: hardened runtime not enabled (${flags:-no flags reported})" ;;
    esac

    # Equality, not presence: Sparkle gates update installation on the host app
    # and its updater sharing a team, so a wrong-team signature would notarize
    # fine and silently break auto-update.
    team=$(printf '%s\n' "$info" | sed -n 's/^TeamIdentifier=//p' | head -1)
    if [ "$team" != "$TEAM_ID" ]; then
        fail "$name: TeamIdentifier is '${team:-unset}', expected '$TEAM_ID'"
    fi

    # A --timestamp signature prints "Timestamp=<date>"; --timestamp=none prints
    # "Signed Time=", which does not match.
    if ! printf '%s\n' "$info" | grep -q '^Timestamp='; then
        fail "$name: no secure timestamp"
    fi
done

if [ "$FAILED" -ne 0 ]; then
    echo "::error::Sparkle signature verification failed" >&2
    exit 1
fi

echo "✅ All ${#COMPONENTS[@]} Sparkle components are Developer ID signed, hardened, timestamped, and team $TEAM_ID"
