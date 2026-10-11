#!/bin/bash
# CI launch/migration gate. This resets test-runner preferences deliberately.
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-}" != true ]]; then
  echo "This smoke test requires an isolated GitHub Actions runner." >&2
  exit 1
fi

app_path=${1:?Pass the built application bundle}
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist")
app_domain=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")
case "$app_domain" in
  app.macdown.macdown3000|app.macdown.macdown3000-debug) ;;
  *) echo "Unexpected application identifier: $app_domain" >&2; exit 1 ;;
esac
binary="$app_path/Contents/MacOS/$executable"
[[ -x "$binary" ]] || { echo "Application executable missing: $binary" >&2; exit 1; }
app_pid=''

cleanup() {
  if [[ -n "$app_pid" ]]; then
    kill -KILL "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
  defaults delete com.uranusjr.macdown 2>/dev/null || true
  defaults delete "$app_domain" 2>/dev/null || true
}
trap cleanup EXIT

launch_and_check() {
  "$binary" -MPDisableUpdater YES -ApplePersistenceIgnoreState YES &
  app_pid=$!
  for ((elapsed=0; elapsed<5; elapsed++)); do
    if ! kill -0 "$app_pid" 2>/dev/null; then
      # Capture the actual application's status, not LaunchServices' open PID.
      wait "$app_pid"
      app_pid=''
      echo "Application exited before the launch observation interval." >&2
      return 1
    fi
    sleep 1
  done
  kill "$app_pid"
  sleep 1
  if kill -0 "$app_pid" 2>/dev/null; then
    kill -KILL "$app_pid" 2>/dev/null || true
  fi
  # SIGTERM is intentional after the observation interval.
  wait "$app_pid" 2>/dev/null || true
  app_pid=''
}

cleanup
launch_and_check
defaults delete "$app_domain" 2>/dev/null || true
defaults write com.uranusjr.macdown testMigrationKey testMigrationValue
defaults write com.uranusjr.macdown editorBaseFontName Monaco
launch_and_check

# Explicit checks avoid Bash 3.2's errexit behavior around substitutions in [[ ]].
expect_default() {
  local actual
  if ! actual=$(defaults read "$app_domain" "$1"); then
    echo "Missing migrated preference: $1" >&2
    return 1
  fi
  if [[ "$actual" != "$2" ]]; then
    echo "Unexpected migrated preference: $1" >&2
    return 1
  fi
}
expect_default MPDidMigrateFromLegacyBundleIdentifier 1 || exit 1
expect_default testMigrationKey testMigrationValue || exit 1
expect_default editorBaseFontName Monaco || exit 1
echo "Application launch and legacy preference migration passed."
