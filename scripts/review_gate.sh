#!/usr/bin/env bash
# review_gate.sh — decide whether a PR carries a genuine independent approval.
#
# Agreed spec (Discussion #196, issue #198, docs/ai-team/README.md §3/§8;
# ADR 0015). The team shares few GitHub accounts, so GitHub authorship cannot
# identify an agent: the account is transport, and the marker is identity. This
# gate reads the team's only reliable identity — one canonical `agent:*` label
# and one canonical non-quoted/non-fenced `**From:** <id>` marker — and passes
# when an approving marker's agent id differs from the PR's `agent:*` lane (an
# agent must not approve its own lane).
#
# The account is NOT a condition of independence (#560): a genuine cross-agent
# review under the shared account and a forged marker pasted under it are
# identical bytes, so the account cannot tell them apart. It is retained only as
# diagnostic and tie-break — a distinct account earns the "corroborated by
# distinct account" PASS tier and ranks which independent approval to headline.
# Marker forgery is out of scope for this gate and is resolved by transcript
# audit (ADR 0015 §3).
#
# Formal GitHub APPROVED and CHANGES_REQUESTED review states are authoritative.
# A COMMENTED review or issue comment may supply a fallback verdict only on one
# explicit logical line: `accept`, `accept with follow-up`, or `changes
# required`, optionally prefixed by `Verdict:` and decorated with a Markdown
# heading or bold. Free prose and quoted/example lines never create or revoke
# an approval or identity. A verdict line may add one bounded `at <token>` or
# `for <token>` context. Marker IDs use lower-case stable-agent segments
# separated by single `.`, `_`, or `-` characters with at most one `/`; case
# and punctuation variants are invalid rather than normalized. A missing,
# repeated, or invalid marker fails closed.
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
elif [[ $# -eq 1 && "$1" =~ ^[0-9]+$ ]]; then
  input=$(mktemp)
  trap 'rm -f "$input"' EXIT
  gh pr view "$1" --json author,labels,reviews,comments >"$input"
else
  echo "usage: $0 <pr-number>   (or REVIEW_GATE_INPUT=<file> $0)" >&2
  exit 1
fi

verdict=$(jq -r '
  def trimmed_line:
    gsub("\\r"; "")
    | gsub("^[[:space:]]+|[[:space:]]+$"; "");
  def indented_code_line($raw):
    $raw | test("^( {4}|[ ]*\\t)");
  def opening_fence:
    (try capture("^(?<fence>(?:\\x60{3,}|~{3,})).*$").fence catch null) // null;
  def closing_fence:
    (try capture("^(?<fence>(?:\\x60{3,}|~{3,}))[ \\t]*$").fence catch null) // null;
  def closes_fence($line; $open):
    ($line | closing_fence) as $close
    | $close != null
      and ($close[0:1] == $open[0:1])
      and (($close | length) >= ($open | length));
  def safe_logical_lines($body):
    reduce ($body | split("\n")[]) as $raw
      ({fence: null, lines: []};
       ($raw | gsub("\\r"; "")) as $raw_line
       | ($raw_line | trimmed_line) as $line
       | if .fence != null then
           if indented_code_line($raw_line) then
             .
           elif closes_fence($line; .fence) then
             .fence = null
           else
             .
           end
         elif indented_code_line($raw_line) or ($line | test("^>")) then
           .
         else
           ($line | opening_fence) as $open
           | if $open == null then .lines += [$line] else .fence = $open end
         end)
    | .lines;
  def canonical_agent_id:
    if type == "string" and
         test("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)?$") then
      .
    else
      null
    end;
  def expected_agent_label($label):
    if ($label | type) == "string" and ($label | startswith("agent:")) then
      ("agent:" + ($label[6:] | gsub("/"; "-"))) as $candidate
      | if ($candidate | test("^agent:[a-z0-9]+(?:[._-][a-z0-9]+)*$")) then
          $candidate
        else
          null
        end
    else
      null
    end;
  def marker_token:
    sub("^#{1,6}[[:space:]]+"; "")
    | try capture("^\\*\\*From:\\*\\*[[:space:]]+(?<id>[^[:space:]]+)(?:[[:space:]].*)?$").id catch null;
  def marker_id($body):
    ([safe_logical_lines($body)[] | marker_token | select(. != null)]) as $markers
    | if ($markers | length) == 1 then
        ($markers[0] | canonical_agent_id)
      else
        null
      end;
  def normalized_verdict_line:
    gsub("\\r"; "")
    | gsub("^[[:space:]]+|[[:space:]]+$"; "")
    | sub("^#{1,6}[[:space:]]+"; "")
    | gsub("\\*\\*"; "")
    # Ending a sentence with a full stop is how English works; "accept." is
    # not a different verdict from "accept" (#597). A question mark is not
    # stripped — "accept?" is genuinely not a verdict.
    | sub("[[:space:]]*[.!]+$"; "");
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
    ([safe_logical_lines($body)[] | normalized_verdict_line | line_verdict | select(. != null)]) as $verdicts
    | if ($verdicts | length) == 1 then
        $verdicts[0]
      elif ($verdicts | any(. == "changes required")) then
        "changes required"
      else
        null
      end;
  def timestamp($value):
    if ($value | type) == "string" then
      try ($value | fromdateiso8601) catch null
    else
      null
    end;
  # A line that starts like a verdict but fails the strict match. Quoted in
  # the no-approval failure so a silent discard becomes a one-second fix by
  # the reviewer — the #586/#590/#597 pattern is the tooling stating a
  # conclusion while withholding the fact needed to act on it.
  def near_miss_lines($body):
    [safe_logical_lines($body)[]
     | normalized_verdict_line
     | select(test("^>") | not)
     | select(line_verdict == null)
     | select(test("(?i)^(verdict:[[:space:]]*)?(accept|changes[[:space:]]+required)\\b"))
     | .[0:80]];

  . as $pr
  | ([$pr.labels[].name | select(startswith("agent:"))]) as $agent_labels
  | ([$pr.reviews[]  | (explicit_verdict(.body)) as $verdict
                        | {account: .author.login, at: timestamp(.submittedAt),
                           state: .state, id: marker_id(.body), verdict: $verdict,
                           changes: (.state == "CHANGES_REQUESTED" or
                                     (.state == "COMMENTED" and $verdict == "changes required")),
                           accept: (.state == "APPROVED" or
                                    (.state == "COMMENTED" and $verdict == "accept"))}]
     + [$pr.comments[] | (explicit_verdict(.body)) as $verdict
                         | {account: .author.login, at: timestamp(.createdAt),
                            state: "COMMENTED", id: marker_id(.body), verdict: $verdict,
                            changes: ($verdict == "changes required"),
                            accept: ($verdict == "accept")}]
    ) as $events
  | ([($pr.reviews[].body // empty), ($pr.comments[].body // empty)]
     | map(near_miss_lines(.)) | add | .[0:3]) as $near_misses
  | if ($agent_labels | length) != 1 then
      "FAIL: PR must carry exactly one agent:* label (found \($agent_labels | length))"
    elif ($agent_labels[0] | test("^agent:[a-z0-9]+(?:[._-][a-z0-9]+)*$") | not) then
      ($agent_labels[0]) as $label
      | (expected_agent_label($label)) as $expected
      | "FAIL: agent label '\''\($label)'\'' is not canonical; labels use lower-case hyphen form"
        + (if $expected != null and $expected != $label then
             " (expected '\''\($expected)'\'')"
           else
             ""
           end)
    elif (($pr.author.login | type) != "string" or $pr.author.login == "") then
      "FAIL: malformed PR author"
    else
      ($agent_labels[0]) as $lane
      | ([$events[] | select(.state != "DISMISSED" and .state != "CHANGES_REQUESTED")
                    | select(.id != null and .accept and (.changes | not) and .at != null)
                    | select((.account | type) == "string" and .account != "")]
         # Ties and malformed relevant timestamps revoke: only a strictly
         # later reapproval can survive every relevant revocation.
         | map(. as $a
             | $a + {revoked: (([$events[]
                       | select(.state == "CHANGES_REQUESTED"
                                or (.changes and .id != null)
                                or (.state == "DISMISSED" and .account == $a.account))
                       | select((.at == null) or (.at >= $a.at))]
                       | length) > 0)})
         | map(select(.revoked | not))) as $approvals
      # Independence is judged on the marker id versus the lane; the account is
      # transport, not identity (ADR 0015, #560). A distinct account is retained
      # only as a tie-break: it ranks which independent approval to headline and
      # earns the "corroborated" tier, never decides whether one is independent.
      | ([$approvals[]
          | select("agent:" + (.id | gsub("/"; "-")) != $lane)]) as $independent
      | ($independent | map(select(.account != $pr.author.login))) as $corroborated
      | if ($approvals | length) == 0 then
          "FAIL: no unrevoked approval verdict found"
          + (if ($near_misses | length) > 0 then
               "; verdict-shaped line(s) did not parse: "
               + ($near_misses | map("\"" + . + "\"") | join(" | "))
             else
               ""
             end)
        elif ($independent | length) == 0 then
          "FAIL: approvals exist but none is independent (lane=\($lane), pr-author=\($pr.author.login))"
        elif ($corroborated | length) > 0 then
          "PASS: independent approval by \($corroborated[0].id) via \($corroborated[0].account) (corroborated by distinct account)"
        else
          "PASS: independent approval by \($independent[0].id) via \($independent[0].account) (marker-attested)"
        end
    end
' "$input")

echo "$verdict"
[[ "$verdict" == PASS:* ]]
