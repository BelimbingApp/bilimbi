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
  contains=$(jq -r '._contains // ""' "$fixture")

  if { [[ "$expect" == pass ]] && [[ $st -eq 0 ]] && [[ "$out" == PASS:* ]]; } ||
     { [[ "$expect" == fail ]] && [[ $st -eq 1 ]] && [[ "$out" == FAIL:* ]]; }; then
    if [[ -n "$contains" && "$out" != *"$contains"* ]]; then
      printf 'FAIL %s (output did not contain %q; output: %.160s)\n' "$name" "$contains" "$out"
      failures=$((failures + 1))
      continue
    fi

    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s (expected %s; exit %s; output: %.160s)\n' "$name" "$expect" "$st" "$out"
    failures=$((failures + 1))
  fi
done

# The fixtures above prove the gate returns the right exit status. They cannot
# see whether the workflow honours it -- and it did not. Assert that the exact
# evaluation step both pipes the gate into `tee` and declares a pipefail shell;
# matching those strings elsewhere in the workflow would not protect the gate.
workflow="$here/../../../.github/workflows/review-gate.yml"

if [[ ! -f "$workflow" ]]; then
  printf 'FAIL wiring (review-gate.yml is missing)\n' >&2
  failures=$((failures + 1))
else
  evaluation_step=$(
    awk '
      /^      - name: Evaluate independent approval[[:space:]]*$/ { capture = 1 }
      capture && /^      - name:/ && !/Evaluate independent approval/ { exit }
      capture { print }
    ' "$workflow"
  )

  if [[ -z "$evaluation_step" ]]; then
    printf 'FAIL wiring (Evaluate independent approval step is missing)\n' >&2
    failures=$((failures + 1))
  elif ! grep -Eq '^        shell: bash -eo pipefail \{0\}[[:space:]]*$' <<<"$evaluation_step"; then
    printf 'FAIL wiring (evaluation step does not declare bash pipefail)\n' >&2
    failures=$((failures + 1))
  elif ! grep -Eq '^[[:space:]]*"\$RUNNER_TEMP/review_gate\.sh"[[:space:]]+"\$PR_NUMBER"[[:space:]]+\|[[:space:]]+tee[[:space:]]+"\$GITHUB_STEP_SUMMARY"[[:space:]]*$' <<<"$evaluation_step"; then
    printf 'FAIL wiring (evaluation step does not pipe the gate into the summary)\n' >&2
    failures=$((failures + 1))
  else
    printf 'ok   wiring (evaluation step cannot swallow the gate verdict)\n'
  fi
fi

if [[ $failures -gt 0 ]]; then
  echo "$failures fixture(s) failed" >&2
  exit 1
fi
echo "all fixtures green"
