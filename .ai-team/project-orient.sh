#!/usr/bin/env bash
# Bilimbi-specific orientation. Keep repository-local project facts here so the
# shared operating guide and its generic mechanisms can move to another repo.

set -u

BLB=${BLB_PATH:-/home/kiat/repo/laravel/blb}
BLB_COMMIT=769bc31ddb632f5d2c5acb0fd05b777197df87cc

echo "== Bilimbi project: canonical Belimbing checkout =="
if [ ! -d "$BLB/app" ]; then
  echo "  MISSING $BLB has no app/ tree — do not cite \"Belimbing\" from anywhere else"
elif ! git -C "$BLB" cat-file -e "${BLB_COMMIT}^{commit}" 2>/dev/null; then
  echo "  WARNING $BLB does not contain ${BLB_COMMIT:0:8} at all — this is not the tree we ported from"
else
  at=$(git -C "$BLB" rev-parse HEAD)
  ahead=$(git -C "$BLB" rev-list --count "${BLB_COMMIT}..HEAD" 2>/dev/null)
  if [ "$at" = "$BLB_COMMIT" ]; then
    echo "  ok      $BLB at ${at:0:8}, the operational citation pin"
  elif git -C "$BLB" merge-base --is-ancestor "$BLB_COMMIT" HEAD 2>/dev/null; then
    echo "  MOVED   $BLB is ${ahead} commit(s) ahead of the pinned ${BLB_COMMIT:0:8} (now ${at:0:8})."
    echo "          Fast-forward, so nothing already cited was rewritten — but these"
    echo "          app/ files changed after the pin, and a port of one of them may"
    echo "          now disagree with its source:"
    git -C "$BLB" diff --name-only "${BLB_COMMIT}..HEAD" -- app/ | sed 's/^/            /'
  else
    echo "  DIVERGED $BLB is at ${at:0:8}; the pinned ${BLB_COMMIT:0:8} is not an ancestor."
    echo "          Citations from it are against a history we did not port."
  fi
fi

echo
echo "== Bilimbi project: installed modules on origin/main =="
descriptors=$(git ls-tree -r --name-only origin/main 2>/dev/null | grep '/bilimbi\.module\.exs$')

for descriptor in $descriptors; do
  git show "origin/main:$descriptor" 2>/dev/null | grep -m1 'id:' | sed 's/^ */  /'
done

if [ -n "$descriptors" ] && ! git diff --quiet origin/main -- $descriptors 2>/dev/null; then
  echo
  echo "  NOTE  your working tree's module descriptors differ from origin/main."
fi

cat <<'TXT'

== Bilimbi project: commands worth knowing ==
  cd apps/core/user && mix test           one module's suite; works without root deps
  cd apps/core/compatibility && mix test  the real gate: migrate + verify against PostgreSQL
  cd apps/web && PORT=4002 mix phx.server serve YOUR branch, then look at it

Never judge a screen from the long-lived dev server on :4000. It belongs to
another checkout and its contribution snapshot is built once at boot.
TXT
