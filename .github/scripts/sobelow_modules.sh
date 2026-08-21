#!/usr/bin/env bash
# Sobelow scans one root, and ADR 0006 moved web adapters into module packages,
# so the apps/web run alone misses most of the attack surface (#547). Scan
# every module package; iterating them all rather than deriving "modules with
# web adapters" means a module that grows its first LiveView is covered the
# day it lands, with no list to go stale. Router-dependent checks still run
# only in the apps/web scan, which keeps its own CI step.
#
# The scan set comes from a pruned find rather than a fixed-depth glob (#603):
# a glob encodes today's nesting depth, and a layout change that merely
# shrinks the match set would leave this scanner reporting success over a
# subset — the one failure mode a security gate must not have. find has no
# depth assumption, and the prunes keep a descriptor inside _build/ or deps/
# from pointing sobelow at vendored code.
#
# Output is captured per module and the exit code computed explicitly, so no
# pipeline can mask a failure. Run from the repository root.

set -u

fail=0

mapfile -t descriptors < <(find apps -name bilimbi.module.exs \
  -not -path '*/_build/*' -not -path '*/deps/*' -not -path '*/node_modules/*' | sort)

if [ "${#descriptors[@]}" -eq 0 ]; then
  echo "FAIL: no module descriptors found below apps/ — the layout changed under this script" >&2
  exit 1
fi

for descriptor in "${descriptors[@]}"; do
  dir=$(dirname "$descriptor")

  echo "== sobelow ${dir}"

  if ! mix sobelow --root "$dir" --private --exit medium; then
    fail=1
  fi
done

exit "$fail"
