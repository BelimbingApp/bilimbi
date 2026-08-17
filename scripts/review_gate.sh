#!/usr/bin/env bash
# review_gate.sh — decide whether a PR carries a genuine independent approval.
#
# Agreed spec (Discussion #196, issue #198, docs/ai-team/README.md §3/§8).
# The team shares two GitHub accounts, so GitHub authorship cannot identify an
# agent and self-approval is blocked natively. This gate reads the team's only
# machine-readable identity — the `agent:*` label and the `**From:** <id>`
# marker — and passes only when BOTH hold:
#
#   1. the approving marker's agent id differs from the PR's `agent:*` label
#      (an agent must not approve its own lane), and
#   2. the approving review/comment's GitHub account differs from the PR
#      author's account (the same agent can paste a marker under the same PAT).
#
# An approval is revoked by a newer CHANGES_REQUESTED review, a newer comment
# carrying the reviewer's `**From:**` marker with a "changes required" verdict,
# or a DISMISSED state on the approving review itself.
#
# Usage:
#   scripts/review_gate.sh <pr-number>     live mode (needs gh + repo)
#   REVIEW_GATE_INPUT=f.json scripts/review_gate.sh   fixture mode (no network)
#
# Exit 0 = independent approval present; exit 1 = absent or indeterminate.
# The indeterminate cases (no `agent:` label, several, malformed data) fail
# closed on purpose: a blind gate must look red, not green.

set -euo pipefail

if [[ -n "${REVIEW_GATE_INPUT:-}" ]]; then
  input="$REVIEW_GATE_INPUT"
elif [[ $# -eq 1 ]]; then
  input=$(mktemp)
  trap 'rm -f "$input"' EXIT
  gh pr view "$1" --json author,labels,reviews,comments >"$input"
else
  echo "usage: $0 <pr-number>   (or REVIEW_GATE_INPUT=<file> $0)" >&2
  exit 1
fi

verdict=$(jq -r '
  def marker_id($body):
    ($body | capture("\\*\\*From:\\*\\*\\s*(?<id>[A-Za-z0-9._/-]+)"; "m").id) // null;
  def says_changes($body): ($body | test("(?i)changes required"));
  def says_accept($body):
    (($body | test("(?i)\\baccept\\b")) and (says_changes($body) | not));

  . as $pr
  | ([$pr.labels[].name | select(startswith("agent:"))]) as $agent_labels
  | ([$pr.reviews[]  | {account: .author.login, at: .submittedAt,
                        state: .state, id: marker_id(.body),
                        changes: says_changes(.body),
                        accept: (says_accept(.body) or .state == "APPROVED")}]
     + [$pr.comments[] | {account: .author.login, at: .createdAt,
                          state: "COMMENTED", id: marker_id(.body),
                          changes: says_changes(.body), accept: says_accept(.body)}]
    ) as $events
  | if ($agent_labels | length) != 1 then
      "FAIL: PR must carry exactly one agent:* label (found \($agent_labels | length))"
    else
      ($agent_labels[0]) as $lane
      | ([$events[] | select(.state != "DISMISSED" and .state != "CHANGES_REQUESTED")
                    | select(.id != null and .accept and (.changes | not))]
         # an approval counts only while no revocation is newer than it
         | map(. as $a
             | $a + {revoked: (([$events[]
                       | select(.at > $a.at)
                       | select(.state == "CHANGES_REQUESTED"
                                or .changes
                                or (.state == "DISMISSED" and .account == $a.account))]
                       | length) > 0)})
         | map(select(.revoked | not))) as $approvals
      | ([$approvals[]
          | select("agent:" + (.id | gsub("/"; "-")) != $lane)
          | select(.account != $pr.author.login)]) as $valid
      | if ($approvals | length) == 0 then
          "FAIL: no unrevoked approval verdict found"
        elif ($valid | length) == 0 then
          "FAIL: approvals exist but none is independent (lane=\($lane), pr-author=\($pr.author.login))"
        else
          "PASS: independent approval by \($valid[0].id) via \($valid[0].account)"
        end
    end
' "$input")

echo "$verdict"
[[ "$verdict" == PASS:* ]]
