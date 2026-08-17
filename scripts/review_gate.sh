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
# Formal GitHub APPROVED and CHANGES_REQUESTED review states are authoritative.
# A COMMENTED review or issue comment may supply a fallback verdict only on one
# explicit logical line: `accept`, `accept with follow-up`, or `changes
# required`, optionally prefixed by `Verdict:` and decorated with a Markdown
# heading or bold. Free prose and quoted/example lines never create or revoke
# an approval. A line may add one bounded `at <token>` or `for <token>` context.
# Several explicit lines are ambiguous and fail closed, except that any explicit
# `changes required` line wins as a rejection. An approval is also revoked by a
# newer formal CHANGES_REQUESTED review, an explicit rejection comment, or a
# DISMISSED state on the approving review itself.
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
  def normalized_verdict_line:
    gsub("\\r"; "")
    | gsub("^[[:space:]]+|[[:space:]]+$"; "")
    | sub("^#{1,6}[[:space:]]+"; "")
    | gsub("\\*\\*"; "");
  def line_verdict:
    if test("^>") then
      null
    elif test("(?i)^(verdict:[[:space:]]*)?accept([[:space:]]+with[[:space:]]+follow-up)?([[:space:]]+(at|for)[[:space:]]+[A-Za-z0-9][A-Za-z0-9._/#:-]{0,127})?$") then
      "accept"
    elif test("(?i)^(verdict:[[:space:]]*)?changes[[:space:]]+required([[:space:]]+(at|for)[[:space:]]+[A-Za-z0-9][A-Za-z0-9._/#:-]{0,127})?$") then
      "changes required"
    else
      null
    end;
  def explicit_verdict($body):
    (reduce ($body | split("\n")[]) as $raw
      ({fenced: false, verdicts: []};
       ($raw | gsub("\\r"; "") | gsub("^[[:space:]]+|[[:space:]]+$"; "")) as $line
       | if ($line | test("^(```|~~~)")) then
           .fenced |= not
         elif .fenced then
           .
         else
           ($line | normalized_verdict_line | line_verdict) as $verdict
           | if $verdict == null then . else .verdicts += [$verdict] end
         end)
      | .verdicts) as $verdicts
    | if ($verdicts | length) == 1 then
        $verdicts[0]
      elif ($verdicts | any(. == "changes required")) then
        "changes required"
      else
        null
      end;

  . as $pr
  | ([$pr.labels[].name | select(startswith("agent:"))]) as $agent_labels
  | ([$pr.reviews[]  | (explicit_verdict(.body)) as $verdict
                        | {account: .author.login, at: .submittedAt,
                           state: .state, id: marker_id(.body), verdict: $verdict,
                           changes: (.state == "CHANGES_REQUESTED" or
                                     (.state == "COMMENTED" and $verdict == "changes required")),
                           accept: (.state == "APPROVED" or
                                    (.state == "COMMENTED" and $verdict == "accept"))}]
     + [$pr.comments[] | (explicit_verdict(.body)) as $verdict
                         | {account: .author.login, at: .createdAt,
                            state: "COMMENTED", id: marker_id(.body), verdict: $verdict,
                            changes: ($verdict == "changes required"),
                            accept: ($verdict == "accept")}]
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
