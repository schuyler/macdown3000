# First, check for git in $PATH
hash git 2>/dev/null || { echo >&2 "Git required, not installed.  Aborting build number update script."; exit 0; }

# Build version (closest-tag-or-branch "-" commits-since-tag "-" short-hash dirty-flag)
function get_build_version() {
    echo $(git describe --tags --always --dirty=+)
}

# Use the latest tag for short version (expected tag format "vn[.n[.n]]")
# or read from version.txt (CURRENT_VERSION or NEXT_VERSION_PLANNED) in development
function get_short_version() {
    LATEST_TAG=$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null) || LATEST_TAG="HEAD"
    if [ $LATEST_TAG = "HEAD" ]; then
        # No tags exist yet, read CURRENT_VERSION from version.txt (initial development)
        local tools_dir=$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")
        local version_file="$tools_dir/version.txt"
        if [ -f "$version_file" ]; then
            SHORT_VERSION=$(grep "^CURRENT_VERSION=" "$version_file" | cut -d= -f2)
        else
            COMMIT_COUNT=$(git rev-list --count HEAD)
            SHORT_VERSION="0.0.$COMMIT_COUNT"
        fi
        COMMIT_COUNT_SINCE_TAG=0
    else
        COMMIT_COUNT_SINCE_TAG=$(git rev-list --count ${LATEST_TAG}..)
        LATEST_TAG=${LATEST_TAG##v} # Remove the "v" from the front of the tag

        if [ $COMMIT_COUNT_SINCE_TAG = 0 ]; then
            # At a release tag, use that version
            SHORT_VERSION="$LATEST_TAG"
        else
            # Between releases (commits after a tag): use NEXT_VERSION_PLANNED as development target
            # This shows development builds progress toward the final target release
            # Example: After v3000.0.0-beta.1 tag, builds show 3000.0.0d5 (5 commits toward final 3000.0.0)
            local tools_dir=$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")
            local version_file="$tools_dir/version.txt"
            if [ -f "$version_file" ]; then
                local next_version=$(grep "^NEXT_VERSION_PLANNED=" "$version_file" | cut -d= -f2)
                SHORT_VERSION="${next_version}d${COMMIT_COUNT_SINCE_TAG}"
            else
                SHORT_VERSION="${LATEST_TAG}d${COMMIT_COUNT_SINCE_TAG}"
            fi
        fi
    fi
    echo $SHORT_VERSION
}

# Bundle version (commits-on-master[-until-branch "." commits-on-branch])
# Assumes that two release branches will not diverge from the same commit on master.
function get_bundle_version() {
    if [ $(git rev-parse --abbrev-ref HEAD) = "master" ]; then
        MASTER_COMMIT_COUNT=$(git rev-list --count HEAD)
        BRANCH_COMMIT_COUNT=0
        BUNDLE_VERSION="$MASTER_COMMIT_COUNT"
    else
        if [ $(git rev-list --count master..) = 0 ]; then   # The branch is attached to master. Just count master.
            MASTER_COMMIT_COUNT=$(git rev-list --count HEAD)
        else
            MASTER_COMMIT_COUNT=$(git rev-list --count $(git rev-list master.. | tail -n 1)^)
        fi
        BRANCH_COMMIT_COUNT=$(git rev-list --count master..)
        if [ $BRANCH_COMMIT_COUNT = 0 ]; then
            BUNDLE_VERSION="$MASTER_COMMIT_COUNT"
        else
            BUNDLE_VERSION="${MASTER_COMMIT_COUNT}.${BRANCH_COMMIT_COUNT}"
        fi
    fi
    echo $BUNDLE_VERSION
}
