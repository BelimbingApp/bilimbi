#!/usr/bin/env python3
"""Keep the AI-team presence board (#208) readable.

Two jobs, both idempotent:

  * **Regenerate the board section** of the issue body from labels and pull
    request state. Everything a coordinating agent needs -- who owns what, what
    is blocked, what is awaiting review -- already exists as `agent:*` and
    `task:*` labels. Writing it by hand lets it drift; deriving it cannot.

  * **Collapse superseded ticks.** Each agent keeps one visible tick comment;
    older ones are minimized as outdated. The protocol always said "post one
    comment and edit it in place" (`docs/ai-team/README.md`), but by the time
    this was written #208 held 95 comments, 76 of them ticks, 63 from a single
    agent -- and only 14 comments had ever been edited. A convention decays
    until something enforces it; this repository already learned that with the
    icon safelist (#219), the descriptor mirror (#201) and the capability
    spelling (#231).

Nothing is ever deleted. Minimizing hides a comment behind a disclosure
triangle and can be undone; deletion cannot. Only comments that carry a tick
marker are eligible, so human instructions on the thread are out of scope by
construction rather than by care.
"""

from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timezone
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BOARD_ISSUE = 208

# Everything between these markers is owned by this script. Anything outside
# them -- the human preamble, standing instructions -- is never touched.
BOARD_BEGIN = "<!-- board:begin -->"
BOARD_END = "<!-- board:end -->"

# The protocol's tick format. The marker is what makes "one comment per agent"
# detectable instead of aspirational.
#
# The alternatives below are not hypothetical: a dry run against #208 found
# five competing presence conventions in use, one per agent, because the
# protocol described the behaviour without fixing the format. They are
# recognised so the sweep works on the board as it actually is.
TICK_MARKER_RES = (
    re.compile(r"<!--\s*tick:([A-Za-z0-9/._@-]+)\s*-->"),
    re.compile(r"<!--\s*agent-presence:\s*([A-Za-z0-9/._@-]+)\s*-->"),
    re.compile(r"<!--\s*presence:agent:([A-Za-z0-9/._@-]+)\s*-->"),
    re.compile(r"<!--\s*agent-heartbeat:\s*([A-Za-z0-9/._@-]+)\s*:"),
)

# Ticks written before any marker existed. Recognised so the first run can tidy
# the backlog it was written for; new ticks should carry the marker.
LEGACY_TICK_RE = re.compile(r"^tick\s+([A-Za-z0-9/._@-]+)\s*[·|]", re.MULTILINE)

# Leading HTML comments are stripped before the legacy check, so a tick that
# opens with a marker is still recognised as opening with "tick".
LEADING_COMMENT_RE = re.compile(r"^\s*(?:<!--.*?-->\s*)+", re.DOTALL)

AGENT_LABEL_PREFIX = "agent:"
TASK_LABEL_PREFIX = "task:"


def tick_agent(body: str | None) -> str | None:
    """The agent a comment ticks for, or None if it is not a tick.

    Checked in marker-first order so an agent that adopts the marker is
    recognised even if their text still opens with the legacy prefix.
    """
    if not body:
        return None

    for pattern in TICK_MARKER_RES:
        marked = pattern.search(body)
        if marked:
            return marked.group(1)

    # Only when the comment *opens* with the legacy form. A review that quotes
    # someone's tick has a line starting "tick " and must not be collapsed.
    stripped = LEADING_COMMENT_RE.sub("", body).lstrip()
    legacy = LEGACY_TICK_RE.search(stripped)
    if legacy and stripped.startswith("tick "):
        return legacy.group(1)

    return None


def supersedable(comments: list[dict]) -> list[dict]:
    """Tick comments that are no longer an agent's latest.

    Order is by comment id rather than timestamp: ids are monotonic per issue
    and immune to clock skew, which matters here because one agent's timestamps
    ran eleven hours ahead for a whole session.
    """
    latest: dict[str, int] = {}
    ticks: list[tuple[str, dict]] = []

    for comment in comments:
        agent = tick_agent(comment.get("body"))
        if agent is None:
            continue
        ticks.append((agent, comment))
        latest[agent] = max(latest.get(agent, 0), comment["id"])

    return [
        comment
        for agent, comment in ticks
        if comment["id"] != latest[agent] and not comment.get("isMinimized")
    ]


def label_names(item: dict) -> tuple[str, ...]:
    return tuple(
        label.get("name", "") for label in item.get("labels", []) if label.get("name")
    )


def owner_of(item: dict) -> str:
    for name in label_names(item):
        if name.startswith(AGENT_LABEL_PREFIX):
            return name[len(AGENT_LABEL_PREFIX) :]
    return "—"


def task_state(item: dict) -> str:
    for name in label_names(item):
        if name.startswith(TASK_LABEL_PREFIX):
            return name[len(TASK_LABEL_PREFIX) :]
    return "—"


def render_board(pulls: list[dict], issues: list[dict], generated_at: str) -> str:
    """The generated section, between its markers."""
    lines = [
        BOARD_BEGIN,
        "",
        "### Board — generated",
        "",
        f"Regenerated from labels and pull request state at **{generated_at}**.",
        "Edits inside this section are overwritten; put anything durable outside it.",
        "",
    ]

    lines.append("#### Open pull requests")
    lines.append("")
    if pulls:
        lines.append("| PR | Owner | State | Title |")
        lines.append("|---|---|---|---|")
        for pull in sorted(pulls, key=lambda p: p["number"]):
            flags = []
            if pull.get("draft"):
                flags.append("draft")
            if "hold:author" in label_names(pull):
                flags.append("**hold:author**")
            state = ", ".join(flags) if flags else "ready"
            title = pull.get("title", "").replace("|", "\\|")[:60]
            lines.append(f"| #{pull['number']} | {owner_of(pull)} | {state} | {title} |")
    else:
        lines.append("None open.")
    lines.append("")

    lines.append("#### Open issues by state")
    lines.append("")
    if issues:
        lines.append("| Issue | Owner | State | Title |")
        lines.append("|---|---|---|---|")
        for issue in sorted(issues, key=lambda i: i["number"]):
            title = issue.get("title", "").replace("|", "\\|")[:60]
            lines.append(
                f"| #{issue['number']} | {owner_of(issue)} | {task_state(issue)} | {title} |"
            )
    else:
        lines.append("None open.")
    lines.append("")
    lines.append(BOARD_END)

    return "\n".join(lines)


def splice_board(body: str | None, section: str) -> str:
    """Replace the generated section, preserving everything around it."""
    body = body or ""

    start = body.find(BOARD_BEGIN)
    end = body.find(BOARD_END)

    if start == -1 or end == -1 or end < start:
        separator = "\n\n" if body.strip() else ""
        return f"{body.rstrip()}{separator}{section}\n"

    return f"{body[:start]}{section}{body[end + len(BOARD_END):]}"


class GitHubAPI:
    def __init__(self, repository: str, token: str):
        self.repository = repository
        self.base_url = f"https://api.github.com/repos/{repository}"
        self.token = token

    def request(self, path: str, method: str = "GET", payload: dict | None = None):
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = Request(
            f"{self.base_url}{path}",
            data=body,
            headers=self._headers(),
            method=method,
        )
        with urlopen(request) as response:
            if response.status == 204:
                return None
            return json.load(response)

    def graphql(self, query: str, variables: dict):
        request = Request(
            "https://api.github.com/graphql",
            data=json.dumps({"query": query, "variables": variables}).encode("utf-8"),
            headers=self._headers(),
            method="POST",
        )
        with urlopen(request) as response:
            payload = json.load(response)
        if payload.get("errors"):
            raise RuntimeError(f"GraphQL error: {payload['errors']}")
        return payload["data"]

    def _headers(self) -> dict[str, str]:
        return {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
            "User-Agent": "bilimbi-board-sweep",
            "X-GitHub-Api-Version": "2022-11-28",
        }

    def paginated(self, path: str, params: dict[str, str]) -> list[dict]:
        results: list[dict] = []
        page = 1
        while True:
            query = urlencode({**params, "per_page": "100", "page": str(page)})
            batch = self.request(f"{path}?{query}")
            results.extend(batch)
            if len(batch) < 100:
                return results
            page += 1

    def open_pulls(self) -> list[dict]:
        return self.paginated("/pulls", {"state": "open"})

    def open_issues(self) -> list[dict]:
        return [
            issue
            for issue in self.paginated("/issues", {"state": "open"})
            if "pull_request" not in issue
        ]

    def board_comments(self) -> list[dict]:
        """Comment id, body and minimized state, oldest first."""
        query = """
        query($owner: String!, $name: String!, $number: Int!, $cursor: String) {
          repository(owner: $owner, name: $name) {
            issue(number: $number) {
              comments(first: 100, after: $cursor) {
                pageInfo { hasNextPage endCursor }
                nodes { id databaseId body isMinimized }
              }
            }
          }
        }
        """
        owner, name = self.repository.split("/", 1)
        cursor = None
        collected: list[dict] = []

        while True:
            data = self.graphql(
                query,
                {"owner": owner, "name": name, "number": BOARD_ISSUE, "cursor": cursor},
            )
            block = data["repository"]["issue"]["comments"]
            for node in block["nodes"]:
                collected.append(
                    {
                        "node_id": node["id"],
                        "id": node["databaseId"],
                        "body": node["body"],
                        "isMinimized": node["isMinimized"],
                    }
                )
            if not block["pageInfo"]["hasNextPage"]:
                return collected
            cursor = block["pageInfo"]["endCursor"]

    def minimize(self, node_id: str) -> None:
        self.graphql(
            """
            mutation($id: ID!) {
              minimizeComment(input: {subjectId: $id, classifier: OUTDATED}) {
                minimizedComment { isMinimized }
              }
            }
            """,
            {"id": node_id},
        )

    def update_board_body(self, body: str) -> None:
        self.request(f"/issues/{BOARD_ISSUE}", "PATCH", {"body": body})


def sweep(api: GitHubAPI, generated_at: str, dry_run: bool = False) -> int:
    section = render_board(api.open_pulls(), api.open_issues(), generated_at)
    issue = api.request(f"/issues/{BOARD_ISSUE}")
    updated = splice_board(issue.get("body"), section)

    if not dry_run and updated != issue.get("body"):
        api.update_board_body(updated)

    collapsed = 0
    for comment in supersedable(api.board_comments()):
        if not dry_run:
            api.minimize(comment["node_id"])
        collapsed += 1

    print(f"board section {'previewed' if dry_run else 'updated'}")
    print(f"superseded ticks {'found' if dry_run else 'collapsed'}: {collapsed}")
    return collapsed


def main() -> int:
    repository = os.environ.get("GITHUB_REPOSITORY")
    token = os.environ.get("GITHUB_TOKEN")

    if not repository or not token:
        print("GITHUB_REPOSITORY and GITHUB_TOKEN are required", file=sys.stderr)
        return 1

    # Falls back to the real clock rather than rendering a blank timestamp: a
    # board that cannot say when it was generated is worse than no board.
    generated_at = os.environ.get("BOARD_GENERATED_AT") or datetime.now(
        timezone.utc
    ).isoformat(timespec="seconds")
    dry_run = os.environ.get("BOARD_DRY_RUN") == "1"

    try:
        sweep(GitHubAPI(repository, token), generated_at, dry_run)
    except HTTPError as error:
        print(f"GitHub API error {error.code}: {error.reason}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
