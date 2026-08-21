#!/usr/bin/env bash
# Sobelow scans one root, and ADR 0006 moved web adapters into module packages,
# so the apps/web run alone misses most of the attack surface (#547). Scan
# every module package; iterating them all rather than deriving "modules with
# web adapters" means a module that grows its first LiveView is covered the
# day it lands, with no list to go stale. Router-dependent checks still run
# only in the apps/web scan, which keeps its own CI step.
#
# Output is captured per module and the exit code computed explicitly, so no
# pipeline can mask a failure. Run from the repository root.

set -u

fail=0
found=0

for descriptor in apps/*/*/bilimbi.module.exs; do
  dir=$(dirname "$descriptor")
  found=1

  echo "== sobelow ${dir}"

  if ! mix sobelow --root "$dir" --private --exit medium; then
    fail=1
  fi
done

if [ "$found" -eq 0 ]; then
  echo "FAIL: no module descriptors found below apps/ — the layout changed under this script" >&2
  exit 1
fi

exit "$fail"
