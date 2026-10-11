#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/utils.sh"

if [[ -n "${MACDOWN_RELEASE_VERSION:-}" || -n "${MACDOWN_RELEASE_BUILD:-}" ]]; then
    # Release inputs also drive Xcode's processed Info.plist. The CLI's compiled
    # constants must describe that same release, including manual builds before
    # GitHub creates the release tag.
    [[ "${MACDOWN_RELEASE_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ &&
       "${MACDOWN_RELEASE_BUILD:-}" =~ ^[0-9]+$ ]] || {
        echo "Release version and numeric build number must both be provided" >&2
        exit 1
    }
    SHORT_VERSION=$MACDOWN_RELEASE_VERSION
    BUNDLE_VERSION=$MACDOWN_RELEASE_BUILD
else
    SHORT_VERSION=$(get_short_version)
    BUNDLE_VERSION=$(get_bundle_version)
fi
# Git tag names become C string literals, never printf format strings.
SHORT_VERSION=${SHORT_VERSION//\\/\\\\}
SHORT_VERSION=${SHORT_VERSION//\"/\\\"}
BUNDLE_VERSION=${BUNDLE_VERSION//\\/\\\\}
BUNDLE_VERSION=${BUNDLE_VERSION//\"/\\\"}
TEMP_HEADER=$(mktemp version.h.XXXXXX)
trap 'rm -f "$TEMP_HEADER"' EXIT
printf '#ifndef VERSION_H\n#define VERSION_H\n\nstatic const char * const kMPApplicationShortVersion = "%s";\nstatic const char * const kMPApplicationBundleVersion = "%s";\n\n#endif\n' \
    "$SHORT_VERSION" "$BUNDLE_VERSION" > "$TEMP_HEADER"
# Keep mtime stable when HEAD/version has not changed, even when invoked by FORCE.
if ! cmp -s "$TEMP_HEADER" version.h; then
    chmod 644 "$TEMP_HEADER"
    mv "$TEMP_HEADER" version.h
fi
