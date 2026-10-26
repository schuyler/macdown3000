#!/bin/bash

if [ "$CI" == "true" ]; then
    echo "Skipping build number update script under CI."
    exit 0
fi

# Source: https://gist.github.com/karlvr/c93a98d7000ecb163895

# This script automatically sets the version and short version string of
# an Xcode project from the Git repository containing the project.
#
# To use this script in Xcode, add the script's path to a "Run Script" build
# phase for your application target.

set -o errexit
set -o nounset

pushd `dirname $0` > /dev/null
source $(pwd -P)/utils.sh
popd > /dev/null

BUILD_VERSION=$(get_build_version)
SHORT_VERSION=$(get_short_version)
BUNDLE_VERSION=$(get_bundle_version)

# Alternatively, we could use Xcode's copy of the Git binary,
# but old Xcodes don't have this.
#GIT=$(xcrun -find git)

# Run Script build phases that operate on product files of the target that defines them should use the value of this build setting [TARGET_BUILD_DIR]. But Run Script build phases that operate on product files of other targets should use “BUILT_PRODUCTS_DIR” instead.
INFO_PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

# A clean build can run this before the processed plist has the version keys,
# so add each key when setting it fails.
set_plist_string() {
    /usr/libexec/PlistBuddy -c "Set :$1 $2" "$INFO_PLIST" 2>/dev/null ||
        /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$INFO_PLIST"
}

set_plist_string CFBundleBuildVersion "$BUILD_VERSION"
set_plist_string CFBundleShortVersionString "$SHORT_VERSION"
set_plist_string CFBundleVersion "$BUNDLE_VERSION"
