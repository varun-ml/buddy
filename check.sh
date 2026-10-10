#!/bin/bash
# Everything a PR must pass, in one place: run it before you push (the pre-push hook does), and CI runs the same script.
#   ./check.sh          build, self-test (incl. one check per regression we've shipped), hook test, snapshots + walk check,
#                       and a scan for private words if you keep a list in ~/.config/buddy/private-words.txt (never in the repo)
set -euo pipefail
cd "$(dirname "$0")"
step() { printf '\n▶ %s\n' "$1"; }

step "build"
swiftc -swift-version 5 -O -suppress-warnings Sources/*.swift -o /tmp/buddy-check

step "self-test (logic, notifications, stats, walking rules, privacy)"
/tmp/buddy-check --selftest

step "hook test (beat.py)"
python3 test_beat.py

step "snapshots, and every buddy's walk must be visible"
rm -rf /tmp/buddy-check-snapshots
if ! out=$(/tmp/buddy-check --snapshot /tmp/buddy-check-snapshots); then echo "$out"; exit 1; fi   # exits 1 if a walk doesn't show

WORDS="$HOME/.config/buddy/private-words.txt"
if [ -f "$WORDS" ]; then
  step "private words (from $WORDS)"
  if git ls-files -z | xargs -0 grep -niwF -f "$WORDS" -- 2>/dev/null; then echo "✗ private words above: remove them before pushing"; exit 1; fi
fi

printf '\n✓ all checks passed\n'
