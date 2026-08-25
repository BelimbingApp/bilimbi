#!/usr/bin/env bash
#
# Claim one ready issue by creating its draft PR. This makes the board check a
# mechanism: no write occurs until both the issue and the open-PR registry say
# that the task is available.
#
#   CLAIM_AGENT=<stable-agent-id> docs/ai-team/scripts/claim.sh <issue-number>
#
# Optional: CLAIM_BRANCH=<branch>, CLAIM_TITLE=<PR title>. The defaults make a
# branch that is easy for this script to recognise on later claim attempts.

set -euo pipefail

issue="${1:-}"
agent="${CLAIM_AGENT:-}"

if [[ $# -ne 1 || ! "$issue" =~ ^[0-9]+$ ]]; then
  echo "usage: CLAIM_AGENT=<stable-agent-id> $0 <issue-number>" >&2
  exit 2
fi

if [[ ! "$agent" =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
  echo "CLAIM_AGENT must be a lower-case stable agent id (without agent:)" >&2
  exit 2
fi

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "not a git checkout" >&2
  exit 2
}
cd "$root"

[[ -z "$(git status --porcelain)" ]] || {
  echo "refusing to switch branches with a dirty worktree" >&2
  exit 2
}

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || {
  echo "cannot resolve the repository from gh" >&2
  exit 2
}

# Read the issue and every open PR before creating a branch, commit, or remote
# ref. GitHub does not offer a transaction across those resources; this is the
# closest useful boundary and every write below is fail-fast.
issue_json=$(gh issue view "$issue" --repo "$repo" --json state,labels,title,url 2>/dev/null) || {
  echo "cannot read issue #$issue from $repo" >&2
  exit 2
}

state=$(jq -r .state <<<"$issue_json")
if [[ "$state" != "OPEN" ]]; then
  echo "refusing #$issue: issue state is $state" >&2
  exit 1
fi

holder=$(jq -r '[.labels[].name | select(startswith("agent:"))] | join(", ")' <<<"$issue_json")
if [[ -n "$holder" ]]; then
  echo "refusing #$issue: already held by $holder" >&2
  exit 1
fi

ready=$(jq -r '[.labels[].name] | any(. == "task:ready")' <<<"$issue_json")
if [[ "$ready" != "true" ]]; then
  echo "refusing #$issue: it is not labelled task:ready" >&2
  exit 1
fi

prs=$(gh pr list --repo "$repo" --state open --limit 100 \
  --json number,title,body,headRefName,labels,url 2>/dev/null) || {
  echo "cannot read open pull requests from $repo" >&2
  exit 2
}

# A normal claim title is "... (#N)". Match that exact issue reference in the
# title or body. Also recognise this script's branch convention only when the
# PR has an owner label, so an unrelated branch cannot block the queue.
matches=$(jq -c --argjson issue "$issue" '
  def agent_labels: [.labels[].name | select(startswith("agent:"))];
  def issue_reference: "(#" + ($issue | tostring) + ")";
  def claim_branch:
    .headRefName | test("(^|[-_/])issue-?" + ($issue | tostring) + "($|[-_/])");
  [.[]
   | select(((((.title // "") + "\\n" + (.body // "")) | contains(issue_reference))
             or ((agent_labels | length) > 0 and claim_branch)))
   | {number, title, url, holders: agent_labels}]
' <<<"$prs")

if [[ $(jq length <<<"$matches") -gt 0 ]]; then
  echo "refusing #$issue: an open PR already holds it:" >&2
  jq -r '.[] | "  #\(.number) [\(.holders | join(", "))] \(.title) — \(.url)"' <<<"$matches" >&2
  exit 1
fi

# Labels on live Issues and PRs are the identity registry. Create the lane label
# only after the claim has passed all availability checks, and before creating a
# branch or PR that would need it.
agent_label="agent:$agent"
labels=$(gh label list --repo "$repo" --limit 1000 --json name 2>/dev/null) || {
  echo "cannot read labels from $repo" >&2
  exit 2
}

if ! jq -e --arg label "$agent_label" 'any(.name == $label)' <<<"$labels" >/dev/null; then
  gh label create "$agent_label" --repo "$repo" --color "5319e7" \
    --description "AI-team identity and ownership: $agent"
fi

branch="${CLAIM_BRANCH:-agent/${agent}-issue-${issue}}"
title="${CLAIM_TITLE:-$(jq -r .title <<<"$issue_json") (#${issue})}"

if git show-ref --verify --quiet "refs/heads/$branch" ||
   git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  echo "refusing #$issue: claim branch $branch already exists" >&2
  exit 1
fi

git fetch -q origin main
git switch -c "$branch" origin/main
git commit --allow-empty -m "claim: #$issue"
git push -u origin "$branch"

body=$(mktemp)
trap 'rm -f "$body"' EXIT
printf '**From:** %s\n\nClaiming #%s through docs/ai-team/scripts/claim.sh.\n' "$agent" "$issue" >"$body"

pr_url=$(gh pr create --repo "$repo" --draft --title "$title" --body-file "$body")
pr=${pr_url##*/}

gh pr edit "$pr" --repo "$repo" --add-label "agent:$agent" --add-label task:active
gh issue edit "$issue" --repo "$repo" --add-label "agent:$agent" --remove-label task:ready --add-label task:active

echo "claimed #$issue in draft PR #$pr ($pr_url) as agent:$agent"
