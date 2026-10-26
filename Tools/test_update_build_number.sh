#!/bin/bash

# Runs update_build_number.sh the way Xcode does, against a processed
# Info.plist that lacks the version keys (a clean build) and one that already
# has stale values (an incremental build), and checks the keys end up holding
# the git-derived versions. Requires macOS (PlistBuddy) and a git checkout.

set -o errexit
set -o nounset

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
source "$SCRIPT_DIR/utils.sh"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

PLIST_PATH="App.app/Contents/Info.plist"
PLIST="$WORK_DIR/$PLIST_PATH"
mkdir -p "$(dirname "$PLIST")"

write_plist() {
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
$1
</dict>
</plist>
PLIST
}

failures=0

check() {
    local label=$1
    if ! CI=false TARGET_BUILD_DIR="$WORK_DIR" INFOPLIST_PATH="$PLIST_PATH" \
            bash "$SCRIPT_DIR/update_build_number.sh"; then
        echo "FAIL ($label): update_build_number.sh exited non-zero"
        failures=$((failures + 1))
        return
    fi

    local key expected actual
    for pair in "CFBundleBuildVersion=$(get_build_version)" \
                "CFBundleShortVersionString=$(get_short_version)" \
                "CFBundleVersion=$(get_bundle_version)"; do
        key=${pair%%=*}
        expected=${pair#*=}
        actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" 2>/dev/null || true)
        if [ "$actual" == "$expected" ]; then
            echo "PASS ($label): $key = $actual"
        else
            echo "FAIL ($label): $key = '$actual', expected '$expected'"
            failures=$((failures + 1))
        fi
    done
}

write_plist ""
check "keys missing"

write_plist "<key>CFBundleBuildVersion</key><string>stale</string>
<key>CFBundleShortVersionString</key><string>stale</string>
<key>CFBundleVersion</key><string>0</string>"
check "keys present"

exit $failures
