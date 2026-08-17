#!/usr/bin/env bash
# Fixture runner for scripts/review_gate.sh. Each *.json here is one case:
# "_expect": "pass"|"fail" plus the exact shape of
# `gh pr view N --json author,labels,reviews,comments`. Runs offline.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
failures=0

for fixture in "$here"/*.json; do
  name=$(basename "$fixture")
  expect=$(jq -r '._expect' "$fixture")
  if REVIEW_GATE_INPUT="$fixture" "$here/../../review_gate.sh" >/dev/null 2>&1; then
    got=pass
  else
    got=fail
  fi
  if [[ "$got" == "$expect" ]]; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s (expected %s, got %s)\n' "$name" "$expect" "$got"
    failures=$((failures + 1))
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "$failures fixture(s) failed" >&2
  exit 1
fi
echo "all fixtures green"
