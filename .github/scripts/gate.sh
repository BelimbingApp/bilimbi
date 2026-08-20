#!/usr/bin/env bash
#
# Gate a pull request merge. Prints every verdict and exits non-zero unless all
# of them pass.
#
#   .github/scripts/gate.sh <pr-number> [<reviewed-sha>]
#
# Run it as its OWN command and chain the merge to it:
#
#   .github/scripts/gate.sh 408 abc1234 \
#     && gh api -X PUT repos/BelimbingApp/bilimbi/pulls/408/merge -f merge_method=merge
#
# Never put the checks and the merge inside one compound command where the merge
# can still run when a check fails. That is exactly how #382 reached main while
# BEHIND it: the check printed its warning and the merge went ahead anyway.
#
# Why a script rather than branch protection: the "Protect main" ruleset does set
# strict_required_status_checks_policy, but it lists both shared human accounts
# as bypass actors with bypass_mode "always" — and those accounts are every agent
# we have. GitHub will not stop us. This will.
#
set -u

PR="${1:-}"
if [ -z "$PR" ]; then
  echo "usage: gate.sh <pr-number> [<reviewed-sha>]" >&2
  exit 2
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not a git checkout" >&2; exit 2; }
cd "$ROOT" || exit 2

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
[ -n "$REPO" ] || { echo "cannot resolve the repository from gh" >&2; exit 2; }

# One fetch of PR state; every check below reads from it.
pr=$(gh pr view "$PR" --repo "$REPO" \
       --json headRefOid,headRefName,isDraft,state,mergeable,labels 2>/dev/null)
[ -n "$pr" ] || { echo "cannot read PR #$PR from $REPO" >&2; exit 2; }

remote_head=$(printf '%s' "$pr" | jq -r .headRefOid)

REVIEWED="${2:-}"
if [ -z "$REVIEWED" ]; then
  REVIEWED="$remote_head"
  echo "note: no reviewed SHA given — gating the current head $REVIEWED."
  echo "      Pass the SHA you actually reviewed, so a push after your review fails this gate."
fi

git fetch -q origin main 2>/dev/null
git cat-file -e "${REVIEWED}^{commit}" 2>/dev/null || git fetch -q origin "pull/$PR/head" 2>/dev/null

fail=0
say_ok()   { echo "  ok      $*"; }
say_bad()  { echo "  BLOCKED $*"; fail=1; }

echo "gate: $REPO #$PR at ${REVIEWED:0:8}"

# 1. Open, and not a draft. A draft is somebody's claim, not a deliverable.
state=$(printf '%s' "$pr" | jq -r .state)
draft=$(printf '%s' "$pr" | jq -r .isDraft)
[ "$state" = "OPEN" ] && say_ok "state is OPEN" || say_bad "state is $state"
[ "$draft" = "false" ] && say_ok "not a draft" || say_bad "PR is a DRAFT — never merge someone's claim"

# 2. Up to date with main. CI green on a tree that never existed on main is not
#    evidence about main. #326 landed red exactly this way.
if git merge-base --is-ancestor origin/main "$REVIEWED" 2>/dev/null; then
  say_ok "contains origin/main ($(git rev-parse --short origin/main))"
else
  say_bad "BEHIND origin/main ($(git rev-parse --short origin/main)) — merge main into the branch first"
fi

# 3. Checks on the REVIEWED sha, not on the PR, not on the branch.
runs=$(gh api "repos/$REPO/commits/$REVIEWED/check-runs" 2>/dev/null)
n=$(printf '%s' "$runs" | jq -r '.check_runs|length' 2>/dev/null || echo 0)
bad=$(printf '%s' "$runs" | jq -r \
      '[.check_runs[]|select(.conclusion!="success" and .conclusion!="skipped")]|length' 2>/dev/null || echo 1)
min=${GATE_MIN_CHECKS:-6}
if [ "${n:-0}" -lt "$min" ] || [ "${bad:-1}" != "0" ]; then
  say_bad "check-runs on ${REVIEWED:0:8}: $n total, $bad not successful (need >=$min, 0 bad)"
  printf '%s' "$runs" | jq -r \
    '.check_runs[]|select(.conclusion!="success" and .conclusion!="skipped")|"            \(.name): \(.status)/\(.conclusion // "pending")"'
else
  say_ok "$n check-runs on ${REVIEWED:0:8}, all successful or skipped"
fi

# 4. Holds. hold:author is the author mid-fix; hold:review is a reviewer with an
#    open finding. Either one stops the merge, and only its owner clears it.
labels=$(printf '%s' "$pr" | jq -r '[.labels[].name]|join(",")')
echo "  labels: ${labels:-none}"
for h in hold:author hold:review; do
  case ",$labels," in
    *",$h,"*) say_bad "$h is set — the label's owner clears it, not you" ;;
    *)        say_ok "no $h" ;;
  esac
done

# 5. The head has not moved since the review. GitHub's PR head also lags a push
#    by minutes, so compare the branch ref too.
if [ "$remote_head" = "$REVIEWED" ]; then
  say_ok "PR head is the reviewed SHA"
else
  say_bad "PR head is ${remote_head:0:8} but you reviewed ${REVIEWED:0:8} — re-review the new head"
fi
# Only meaningful while the PR is open: the branch is normally deleted on merge,
# and that 404 means "merged", not "diverged".
if [ "$state" = "OPEN" ]; then
  branch=$(printf '%s' "$pr" | jq -r .headRefName)
  ref=$(gh api "repos/$REPO/git/refs/heads/$branch" --jq .object.sha 2>/dev/null)
  case "$ref" in
    [0-9a-f][0-9a-f]*)
      [ "$ref" = "$remote_head" ] \
        || say_bad "branch $branch is at ${ref:0:8} but the PR head says ${remote_head:0:8} — a push has not propagated yet" ;;
    *) echo "  note: no branch ref for $branch (deleted, or a fork)" ;;
  esac
fi

# 6. Conflicts. mergeStateStatus is permanently BLOCKED for us and carries no
#    information; mergeable does.
mergeable=$(printf '%s' "$pr" | jq -r .mergeable)
[ "$mergeable" = "CONFLICTING" ] && say_bad "CONFLICTING with the base branch" || say_ok "mergeable: $mergeable"

# 7. Not a check — the last word on the PR, so a hold written as prose by
#    somebody who did not know about the label is still in front of you.
echo "  --- last 3 comments ---"
gh pr view "$PR" --repo "$REPO" --json comments \
  --jq '.comments[-3:][]|"            \(.createdAt) \(.author.login): \(.body[0:100]|gsub("\n";" "))"' 2>/dev/null

if [ "$fail" = "0" ]; then
  echo "GATE: PASS"
else
  echo "GATE: FAIL"
fi
exit "$fail"
