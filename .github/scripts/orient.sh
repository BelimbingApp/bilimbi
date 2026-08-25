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

# A halt must reach every agent regardless of tool, so it lives on the board and
# surfaces here — the one command every agent runs each tick. An open issue
# labelled `ops:halt` means the team stands down; it is set and cleared by the
# owner, or the steward on the owner's word. Printed first so a stand-down that
# went out on one tool's private channel is not missed by agents on another.
echo "== operations =="
halt=$(gh issue list --repo "$REPO" --state open --label "ops:halt" \
         --json number,title --jq '.[]|"  HALT #\(.number) — \(.title)"' 2>/dev/null)
if [ -n "$halt" ]; then
  echo "  *** STAND DOWN — a halt is active ***"
  printf '%s\n' "$halt"
  echo "  Finish or hand off your current PR, run .github/scripts/cleanup.sh,"
  echo "  cancel your heartbeat and any watcher, and go silent. Stop is not idle."
else
  echo "  ok      no halt active"
fi
echo

BLB=${BLB_PATH:-/home/kiat/repo/laravel/blb}
# Operational citation pin for the Belimbing checkout agents read. Historical
# compatibility citations may intentionally name older commits; do not rewrite
# those unless the compatibility decision itself changes.
BLB_COMMIT=769bc31ddb632f5d2c5acb0fd05b777197df87cc

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
echo "== holds that have been addressed — the author pushed after the label =="
# A hold transfers the obligation to whoever set it, and nothing else tells that
# person when it comes due. I once left `hold:review` on a PR for 75 minutes
# after the author had already fixed it, because I was working on something else
# and never re-checked the thing I was blocking (#431).
#
# Every agent commits as the same handle, so the API cannot say WHICH agent set a
# label. All open holds are listed rather than filtered to yours: the cost of
# seeing someone else's is one glance, and the cost of hiding your own is the
# 75 minutes.
held=$(gh pr list --repo "$REPO" --state open --limit 60 \
         --json number,labels,title \
         --jq '.[]|select([.labels[].name]|any(startswith("hold:")))|"\(.number)\t\([.labels[].name]|map(select(startswith("hold:")))|join(","))\t\(.title[0:52])"' 2>/dev/null)

if [ -z "$held" ]; then
  echo "  none"
else
  printf '%s\n' "$held" | while IFS=$'\t' read -r n labels title; do
    # Latest application of any hold label; a hold can be set, cleared and set again.
    set_at=$(gh api "repos/$REPO/issues/$n/timeline" --paginate \
      --jq '[.[]|select(.event=="labeled" and (.label.name|startswith("hold:")))|.created_at]|last' 2>/dev/null)
    head_at=$(gh api "repos/$REPO/pulls/$n/commits" \
      --jq '[.[]|.commit.committer.date]|last' 2>/dev/null)
    echo "  #$n [$labels] $title"

    if [ -n "$set_at" ] && [ -n "$head_at" ]; then
      s_e=$(date -d "$set_at" +%s 2>/dev/null)
      h_e=$(date -d "$head_at" +%s 2>/dev/null)
      if [ -n "$s_e" ] && [ -n "$h_e" ] && [ "$h_e" -gt "$s_e" ]; then
        mins=$(( (h_e - s_e) / 60 ))
        waited=$(( ($(date +%s) - h_e) / 60 ))
        echo "        label set $set_at, head pushed +${mins}m later — WAITING ${waited}m. Re-review or clear."
      else
        echo "        no push since the label — the ball is with the author."
      fi
    fi
  done
fi

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
echo "== installed modules on origin/main =="
# Read the descriptors out of origin/main, not the working tree. This used to
# grep `apps/*/*/bilimbi.module.exs` on disk, which silently reports whatever
# branch -- or whatever stale checkout -- the script happens to run from. It
# listed a main that was missing two merged modules, and nothing said so.
descriptors=$(git ls-tree -r --name-only origin/main 2>/dev/null | grep '/bilimbi\.module\.exs$')

for descriptor in $descriptors; do
  git show "origin/main:$descriptor" 2>/dev/null | grep -m1 'id:' | sed 's/^ */  /'
done

if [ -n "$descriptors" ] && ! git diff --quiet origin/main -- $descriptors 2>/dev/null; then
  echo
  echo "  NOTE  your working tree's module descriptors differ from origin/main."
fi

cat <<'TXT'

== the commands worth knowing ==
  cd apps/core/user && mix test          one module's suite; works without root deps
  cd apps/core/compatibility && mix test  the real gate: migrate + verify against PostgreSQL
  cd apps/web && PORT=4002 mix phx.server serve YOUR branch, then look at it

Never judge a screen from the long-lived dev server on :4000. It is somebody
else's checkout and its contribution snapshot is built once at boot, so a merged
fix is simply absent there. Twice in one day that was mistaken for a defect.
TXT
