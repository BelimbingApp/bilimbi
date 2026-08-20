#!/usr/bin/env bash
# Fixture runner for scripts/review_gate.sh. Each *.json here is one case:
# "_expect": "pass"|"fail" plus the exact shape of
# `gh pr view N --json author,labels,reviews,comments`. Runs offline.
#
# A fixture only counts as green when the gate exits with the expected
# status AND verdict line — a crash is never a pass, not even for a
# fail-expected fixture.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
gate="$here/../../review_gate.sh"
failures=0

for fixture in "$here"/*.json; do
  name=$(basename "$fixture")
  expect=$(jq -r '._expect // ""' "$fixture")
  if [[ "$expect" != pass && "$expect" != fail ]]; then
    printf 'FAIL %s (bad _expect %q)\n' "$name" "$expect"
    failures=$((failures + 1))
    continue
  fi

  out=$(REVIEW_GATE_INPUT="$fixture" "$gate" 2>&1) && st=0 || st=$?

  if { [[ "$expect" == pass ]] && [[ $st -eq 0 ]] && [[ "$out" == PASS:* ]]; } ||
     { [[ "$expect" == fail ]] && [[ $st -eq 1 ]] && [[ "$out" == FAIL:* ]]; }; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s (expected %s; exit %s; output: %.160s)\n' "$name" "$expect" "$st" "$out"
    failures=$((failures + 1))
  fi
done

# The fixtures above prove the gate returns the right exit status. They cannot
# see whether the workflow honours it -- and it did not. The step piped the gate
# into `tee`, and a `run:` block with no explicit `shell:` runs under
# `bash -e {0}`, which has no `pipefail`, so the pipeline reported `tee`'s
# status. #499, #503 and #505 all merged with zero reviews and a green
# "Independent review present" (#516). This asserts the half no fixture covers.
workflow="$here/../../../.github/workflows/review-gate.yml"

if [[ -f "$workflow" ]]; then
  if grep -Eq 'review_gate\.sh".*\|' "$workflow" && ! grep -q 'set -o pipefail' "$workflow"; then
    printf 'FAIL wiring (review-gate.yml pipes the gate without pipefail; the verdict cannot fail the check)\n' >&2
    failures=$((failures + 1))
  else
    printf 'ok   wiring (review-gate.yml cannot swallow the gate verdict)\n'
  fi
fi

if [[ $failures -gt 0 ]]; then
  echo "$failures fixture(s) failed" >&2
  exit 1
fi
echo "all fixtures green"
