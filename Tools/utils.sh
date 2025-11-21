# First, check for git in $PATH
hash git 2>/dev/null || { echo >&2 "Git required, not installed.  Aborting build number update script."; exit 0; }

# Build version (closest-tag-or-branch "-" commits-since-tag "-" short-hash dirty-flag)
# Uses standard git describe format
function get_build_version() {
    git describe --tags --always --dirty=+
}

# Short version (user-facing version string)
# Uses git tags as single source of truth
# Examples:
#   On tag v3000.0.0-beta.1     → "3000.0.0-beta.1"
#   5 commits after tag         → "3000.0.0-beta.1.post5"
#   No tags yet                 → "0.0.0.dev<commit-count>"
function get_short_version() {
    local LATEST_TAG=$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null)

    if [ -z "$LATEST_TAG" ]; then
        # No tags exist yet - use commit count as development version
        local COMMIT_COUNT=$(git rev-list --count HEAD)
        echo "0.0.0.dev${COMMIT_COUNT}"
    else
        # Remove 'v' prefix from tag
        local VERSION="${LATEST_TAG#v}"
        local COMMIT_COUNT_SINCE_TAG=$(git rev-list --count ${LATEST_TAG}..HEAD)

        if [ $COMMIT_COUNT_SINCE_TAG -eq 0 ]; then
            # Exactly on a release tag
            echo "$VERSION"
        else
            # Post-release development build
            # Use .postN suffix (PEP 440 style, more standard than "dN")
            echo "${VERSION}.post${COMMIT_COUNT_SINCE_TAG}"
        fi
    fi
}

# Bundle version (build number for CFBundleVersion)
# Uses total commit count for monotonically increasing build numbers
function get_bundle_version() {
    git rev-list --count HEAD
}
