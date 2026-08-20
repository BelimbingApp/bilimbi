#!/usr/bin/env bash
#
# Everything a teammate needs to start working, in one command.
#
#   .github/scripts/orient.sh
#
# This exists because orientation is our largest repeated cost: every agent that
# starts pays for it, and the short-lived ones pay for it once per task. Prose
# cannot tell you who holds a file right now; this can.
#
set -u

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not a git checkout" >&2; exit 2; }
cd "$ROOT" || exit 2
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo BelimbingApp/bilimbi)

BLB=${BLB_PATH:-/home/kiat/repo/laravel/blb}
BLB_COMMIT=e70b4d33c0b10790e681f4c2b5095d85a53bc918

echo "== canonical Belimbing checkout =="
# Citing the wrong tree has actually happened: /home/kiat/repo/Belimbing is
# planning material with no app/ directory, so a grep there finds nothing and
# "not in Belimbing" gets written up as an invention.
if [ ! -d "$BLB/app" ]; then
  echo "  MISSING $BLB has no app/ tree — do not cite \"Belimbing\" from anywhere else"
elif ! git -C "$BLB" cat-file -e "${BLB_COMMIT}^{commit}" 2>/dev/null; then
  echo "  WARNING $BLB does not contain ${BLB_COMMIT:0:8} at all — this is not the tree we ported from"
else
  at=$(git -C "$BLB" rev-parse HEAD)
  ahead=$(git -C "$BLB" rev-list --count "${BLB_COMMIT}..HEAD" 2>/dev/null)
  if [ "$at" = "$BLB_COMMIT" ]; then
    echo "  ok      $BLB at ${at:0:8}, the commit this port targets"
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
echo "== main =="
git fetch -q origin main 2>/dev/null
echo "  origin/main  $(git log origin/main --oneline -1)"
branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" != "main" ]; then
  if git merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
    echo "  $branch: contains origin/main"
  else
    echo "  $branch: BEHIND origin/main — merge it in before you ask anyone to review"
  fi
fi

echo
echo "== open pull requests — who holds what =="
gh pr list --repo "$REPO" --state open --limit 40 \
  --json number,title,isDraft,labels,headRefName \
  --jq '.[]|"  #\(.number) \(if .isDraft then "[draft]" else "        " end) \(.title[0:62])
        \(.headRefName)  \([.labels[].name]|join(" "))"' 2>/dev/null \
  || echo "  (gh unavailable)"

echo
echo "== ready and unclaimed — no agent:* label =="
gh issue list --repo "$REPO" --state open --label "task:ready" --limit 40 \
  --json number,title,labels \
  --jq '.[]|select([.labels[].name]|any(startswith("agent:"))|not)|"  #\(.number) \(.title[0:70])"' 2>/dev/null \
  || echo "  (gh unavailable)"

echo
echo "== blocked =="
gh issue list --repo "$REPO" --state open --label "task:blocked" --limit 40 \
  --json number,title --jq '.[]|"  #\(.number) \(.title[0:70])"' 2>/dev/null

echo
echo "== label hygiene — these are invisible to the queries above =="
gh issue list --repo "$REPO" --state open --label "task:done" --limit 40 \
  --json number,title --jq '.[]|"  #\(.number) OPEN but labelled task:done — \(.title[0:56])"' 2>/dev/null
gh issue list --repo "$REPO" --state open --limit 100 --json number,title,labels \
  --jq '[.[]|select([.labels[].name]|map(select(startswith("task:")))|length > 1)]
        |.[]|"  #\(.number) carries two task:* labels — \(.title[0:56])"' 2>/dev/null

echo
echo "== installed modules, in resolved order =="
grep -h 'id:' apps/*/*/bilimbi.module.exs 2>/dev/null | sed 's/^ *//' | sed 's/^/  /'

cat <<'TXT'

== the commands worth knowing ==
  cd apps/core/user && mix test          one module's suite; works without root deps
  cd apps/core/compatibility && mix test  the real gate: migrate + verify against PostgreSQL
  cd apps/web && PORT=4002 mix phx.server serve YOUR branch, then look at it

Never judge a screen from the long-lived dev server on :4000. It is somebody
else's checkout and its contribution snapshot is built once at boot, so a merged
fix is simply absent there. Twice in one day that was mistaken for a defect.
TXT
