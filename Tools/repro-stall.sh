#!/bin/bash
#
# Reproduce the intermittent test-host stall that shows up on GitHub Actions runners.
#
# Symptom: a test emits "Test Case '…' started." and the run goes silent. Sometimes
# XCTest's execution-time-allowance watchdog fires and recovers the suite, sometimes it
# fires and the host never resumes, sometimes it never reports at all. On CI this costs
# either a watchdog recovery or the whole job timeout.
#
# The trigger is scheduling pressure, not GitHub. Running the suite at background QoS
# (taskpolicy -b) starves the test host for CPU and I/O and reproduces the stall on
# developer hardware, where it otherwise never appears. Background QoS is used rather than
# saturating the machine so foreground apps stay responsive while this runs.
#
# Observed victims are tests that wait on real asynchronous delivery inside a timed wait —
# MPWordCountUpdateTests, MPResourceWatcherSetTests, MPPreviewViewControllerTests. The
# specific victim varies between runs; what stays constant is that one of them wedges.
#
# usage: Tools/repro-stall.sh [iterations] [allowance_seconds]
#
#   iterations  how many full-suite runs to attempt (default 12)
#   allowance   -maximum-test-execution-time-allowance, seconds (default 60). Lower values
#               surface a wedge faster; too low and a merely-slow test is misreported.
#
# Each run is classified:
#   ok     tests executed, no wedge
#   WEDGE  watchdog fired and/or the host restarted; the victim is named
#   NORUN  no tests executed at all (usually a build failure — run `bundle exec pod install`).
#          This case exists because a build failure produces no wedge markers and would
#          otherwise be scored as a pass.

set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO" || exit 1

ITER=${1:-12}
ALLOW=${2:-60}
OUT=${TMPDIR:-/tmp}/macdown-repro-stall
mkdir -p "$OUT"

echo "repo=$REPO"
echo "iterations=$ITER allowance=${ALLOW}s  (background QoS via taskpolicy -b)"
echo "logs=$OUT"
echo "start $(date +%H:%M:%S)"

wedges=0
noruns=0
for i in $(seq 1 "$ITER"); do
  log="$OUT/run-$i.log"
  start=$(date +%s)
  CI=true taskpolicy -b xcodebuild test \
    -workspace "MacDown 3000.xcworkspace" \
    -scheme MacDown \
    -destination 'platform=macOS' \
    -test-timeouts-enabled YES \
    -maximum-test-execution-time-allowance "$ALLOW" \
    > "$log" 2>&1
  dur=$(( $(date +%s) - start ))

  hung=$(grep -c "exceeded execution time allowance" "$log")
  restart=$(grep -c "Restarting after" "$log")
  total=$(grep -oE "Executed [0-9]+ tests, with [0-9]+ failures \([0-9]+ unexpected\)" "$log" | tail -1)

  if [ -z "$total" ] && [ "$hung" -eq 0 ] && [ "$restart" -eq 0 ]; then
    noruns=$((noruns + 1))
    reason=$(grep -aoE "error: .{0,90}" "$log" | head -1)
    printf "run %-3s %4ss  NORUN  %s\n" "$i" "$dur" "${reason:-no tests executed, cause unknown}"
  elif [ "$hung" -gt 0 ] || [ "$restart" -gt 0 ]; then
    wedges=$((wedges + 1))
    victim=$(grep -oE "Test Case '[^']*' exceeded execution time allowance" "$log" \
             | sed "s/Test Case '//;s/' exceeded.*//" | sort -u | tr '\n' ' ')
    printf "run %-3s %4ss  WEDGE  %s\n" "$i" "$dur" "${victim:-victim not named; see $log}"
  else
    printf "run %-3s %4ss  ok     %s\n" "$i" "$dur" "$total"
  fi
done

echo "done $(date +%H:%M:%S) — $wedges/$ITER wedged, $noruns/$ITER did not run"
[ "$wedges" -gt 0 ] && exit 1
exit 0
