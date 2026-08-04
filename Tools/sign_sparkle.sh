#!/bin/bash
#
# Re-sign Sparkle's nested components with the release signing identity.
#
# Sparkle ships from CocoaPods ad-hoc signed, and the "[CP] Embed Pods
# Frameworks" phase re-signs only the framework's top level, without
# --options runtime or --timestamp. Notarization rejects the result: the nested
# executables carry no Developer ID signature and no secure timestamp, and the
# framework binary loses its hardened-runtime flag.
#
# Components are signed innermost first. Each signature invalidates the seal of
# everything enclosing it, so the framework is signed last -- and the caller
# must re-sign the app bundle afterwards to re-seal its resources.
#
# Usage: bash Tools/sign_sparkle.sh <identity> <path-to-Sparkle.framework>

set -o errexit
set -o nounset
set -o pipefail

IDENTITY="${1:-}"
FRAMEWORK_ARG="${2:-}"

if [ -z "$IDENTITY" ] || [ -z "$FRAMEWORK_ARG" ]; then
    echo "::error::usage: sign_sparkle.sh <identity> <path-to-Sparkle.framework>" >&2
    exit 1
fi

if [ ! -d "$FRAMEWORK_ARG" ]; then
    echo "::error::Sparkle.framework not found at: $FRAMEWORK_ARG" >&2
    exit 1
fi

FRAMEWORK=$(cd "$FRAMEWORK_ARG" && pwd -P)

# Signing the CocoaPods source copy has no effect on the shipped app, but leaves
# the release looking green until notarization rejects it.
case "$FRAMEWORK" in
    */Pods/*)
        echo "::error::refusing to sign the CocoaPods source copy: $FRAMEWORK" >&2
        echo "::error::pass the embedded copy under <app>/Contents/Frameworks" >&2
        exit 1
        ;;
esac

if [ ! -d "$FRAMEWORK/Versions/Current" ]; then
    echo "::error::$FRAMEWORK has no Versions/Current" >&2
    exit 1
fi
VERSION_DIR=$(cd "$FRAMEWORK/Versions/Current" && pwd -P)

# Sparkle 2.9.5's signable components, innermost first. Sparkle is pinned in
# Podfile.lock, so this list is exact rather than discovered; the two checks
# below fail loudly if an upgrade invalidates it.
COMPONENTS=(
    "$VERSION_DIR/XPCServices/Downloader.xpc"
    "$VERSION_DIR/XPCServices/Installer.xpc"
    "$VERSION_DIR/Updater.app"
    "$VERSION_DIR/Autoupdate"
    "$FRAMEWORK"
)
EXPECTED_MACHO_COUNT=5

# Tripwire 1: a renamed or removed component.
for component in "${COMPONENTS[@]}"; do
    if [ ! -e "$component" ]; then
        echo "::error::expected Sparkle component is missing: $component" >&2
        echo "::error::Sparkle's layout changed; update COMPONENTS in Tools/sign_sparkle.sh and Tools/verify_sparkle_signature.sh" >&2
        exit 1
    fi
done

# Tripwire 2: an added component. codesign without --deep seals a nested
# bundle's existing signature rather than replacing it, so anything new would
# ship ad-hoc inside a validly-sealed framework.
#
# `file` reports a universal binary on several lines -- one summary plus one per
# architecture -- so per-architecture lines are dropped to count files, not slices.
MACHO_COUNT=$(find "$VERSION_DIR" -type f -exec file {} + \
    | grep -v "(for architecture" \
    | grep -c "Mach-O" || true)
if [ "$MACHO_COUNT" -ne "$EXPECTED_MACHO_COUNT" ]; then
    echo "::error::expected $EXPECTED_MACHO_COUNT Mach-O binaries under $VERSION_DIR, found $MACHO_COUNT" >&2
    echo "::error::Sparkle's layout changed; update COMPONENTS in Tools/sign_sparkle.sh and Tools/verify_sparkle_signature.sh" >&2
    exit 1
fi

# --preserve-metadata=identifier,entitlements keeps Autoupdate's
# com.apple.application-identifier entitlement. This diverges from Sparkle's own
# documentation, which strips it -- deliberately: shipping notarized Sparkle apps
# (Rectangle, NordVPN, Scrivener) all preserve it under a Developer ID signature,
# so Apple's notary service accepts it, and preserving is the conservative
# choice. The designated requirement is NOT preserved, so it regenerates from
# the signing identity.
#
# Retries cover Apple's timestamp service rate-limiting; without them a transient
# 5xx aborts the release after the archive build has already been paid for. The
# predicate is a denylist because codesign's timestamp-error wording is not
# stable across macOS versions -- an allowlist would silently stop retrying.
# Retrying is safe: --force rebuilds the signature from scratch, and a timestamp
# failure exits non-zero before anything is committed.
sign_component() {
    local component="$1"
    local name attempt delay output
    name=$(basename "$component")
    attempt=1
    delay=2

    while :; do
        # Written as `if !` because `set -e` would otherwise abort the script
        # before this loop could observe the failure.
        if output=$(codesign --force --sign "$IDENTITY" \
                        --options runtime \
                        --timestamp \
                        --preserve-metadata=identifier,entitlements \
                        "$component" 2>&1); then
            # codesign reports on stderr even on success; keep it in the CI log,
            # matching the other signing calls in release.yml.
            if [ -n "$output" ]; then
                printf '%s\n' "$output"
            fi
            return 0
        fi

        printf '%s\n' "$output" >&2

        case "$output" in
            *"no identity found"*|*"unable to build chain"*|*"bundle format unrecognized"*|*"is not signable"*)
                echo "::error::codesign failed for $name (not retryable)" >&2
                return 1
                ;;
        esac

        if [ "$attempt" -ge 5 ]; then
            echo "::error::codesign failed for $name after $attempt attempts" >&2
            return 1
        fi

        echo "codesign attempt $attempt failed for $name; retrying in ${delay}s"
        sleep "$delay"
        attempt=$((attempt + 1))
        delay=$((delay * 2))
    done
}

for component in "${COMPONENTS[@]}"; do
    echo "🔐 Signing $(basename "$component")..."
    sign_component "$component"
done

echo "✅ Signed ${#COMPONENTS[@]} Sparkle components"
echo "ℹ️  The app bundle must be re-signed after this to re-seal its resources."
