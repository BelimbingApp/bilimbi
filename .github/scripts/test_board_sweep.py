"""Tests for the presence-board sweep.

The two that matter most are `test_never_collapses_a_human_comment` and
`test_preserves_everything_outside_the_markers`. This script edits the one
issue the team coordinates through, and both failure modes -- hiding a
standing instruction, or overwriting the human preamble -- would be discovered
by someone noticing their words had gone.
"""

from __future__ import annotations

import unittest

from board_sweep import (
    BOARD_BEGIN,
    BOARD_END,
    render_board,
    splice_board,
    supersedable,
    tick_agent,
)


def comment(cid: int, body: str, minimized: bool = False) -> dict:
    return {"id": cid, "node_id": f"n{cid}", "body": body, "isMinimized": minimized}


class TickRecognition(unittest.TestCase):
    def test_marker_form(self):
        self.assertEqual(tick_agent("<!-- tick:claude-opus-5 -->\nwork"), "claude-opus-5")

    def test_legacy_form(self):
        self.assertEqual(
            tick_agent("tick antigravity · 2026-08-18T20:40:00+08:00 · opened PR"),
            "antigravity",
        )

    def test_agent_ids_with_slashes_and_dots(self):
        self.assertEqual(
            tick_agent("tick opencode/deepseek-v4-pro · 2026-08-18 · x"),
            "opencode/deepseek-v4-pro",
        )
        self.assertEqual(tick_agent("<!-- tick:amp/kimi-k3 -->"), "amp/kimi-k3")

    def test_recognises_the_conventions_agents_actually_use(self):
        # A dry run against #208 found five competing formats, one per agent.
        # The sweep has to work on the board as it is, not as the protocol
        # wishes it were.
        self.assertEqual(
            tick_agent("<!-- agent-presence: faith-toh --> tick faith-toh \u00b7 x"),
            "faith-toh",
        )
        self.assertEqual(
            tick_agent("<!-- presence:agent:antigravity --> ### Presence Tick"),
            "antigravity",
        )
        self.assertEqual(
            tick_agent("<!-- agent-heartbeat: kiatng/antigravity: 2026-08-19 --> x"),
            "kiatng/antigravity",
        )

    def test_never_claims_the_shared_board_comment(self):
        # `presence:bilimbi:ai-team` marks the team's shared board summary, not
        # any one agent's tick. Collapsing it would delete the board itself
        # from view, so it must not parse as a tick.
        self.assertIsNone(
            tick_agent("<!-- presence:bilimbi:ai-team --> ### Bilimbi AI Team Presence")
        )

    def test_prose_mentioning_a_tick_is_not_a_tick(self):
        # The legacy form only counts when the comment *opens* with it, so a
        # review that discusses ticks is not mistaken for one.
        self.assertIsNone(
            tick_agent("I noticed tick antigravity · 2026-08-18 · was duplicated")
        )

    def test_a_comment_quoting_a_tick_is_not_a_tick(self):
        # The dangerous case, and the one the `startswith` guard exists for: a
        # review that quotes someone's tick has a *line* beginning "tick ",
        # which the multiline regex matches. Without the guard that reviewer's
        # comment would be collapsed as a superseded tick. Mutation testing
        # found this hole -- the earlier version put the phrase mid-line, where
        # the anchor alone rejects it and the guard is never exercised.
        quoted = (
            "Reviewing the board:\n"
            "tick antigravity \u00b7 2026-08-18T20:40:00+08:00 \u00b7 opened PR #321\n"
            "that entry contradicts #334."
        )
        self.assertIsNone(tick_agent(quoted))

    def test_human_instruction_is_not_a_tick(self):
        self.assertIsNone(
            tick_agent("From owner: when the PR has a label hold:author do not merge")
        )

    def test_empty_and_missing_bodies(self):
        self.assertIsNone(tick_agent(""))
        self.assertIsNone(tick_agent(None))


class Superseding(unittest.TestCase):
    def test_keeps_the_newest_per_agent(self):
        comments = [
            comment(1, "<!-- tick:a -->old"),
            comment(2, "<!-- tick:a -->newer"),
            comment(3, "<!-- tick:b -->only"),
        ]
        self.assertEqual([c["id"] for c in supersedable(comments)], [1])

    def test_never_collapses_a_human_comment(self):
        comments = [
            comment(1, "<!-- tick:a -->old"),
            comment(2, "From owner: do not merge anything labelled hold:author"),
            comment(3, "**From:** claude/opus-5 — review findings"),
            comment(4, "<!-- tick:a -->newest"),
        ]
        collapsed = [c["id"] for c in supersedable(comments)]
        self.assertEqual(collapsed, [1])
        self.assertNotIn(2, collapsed)
        self.assertNotIn(3, collapsed)

    def test_skips_already_minimized(self):
        comments = [
            comment(1, "<!-- tick:a -->old", minimized=True),
            comment(2, "<!-- tick:a -->newest"),
        ]
        self.assertEqual(supersedable(comments), [])

    def test_orders_by_id_not_position(self):
        # Ids are monotonic; timestamps are not trustworthy here, because one
        # agent's clock ran eleven hours ahead for a whole session.
        comments = [comment(9, "<!-- tick:a -->newest"), comment(4, "<!-- tick:a -->old")]
        self.assertEqual([c["id"] for c in supersedable(comments)], [4])

    def test_a_single_tick_is_never_collapsed(self):
        self.assertEqual(supersedable([comment(1, "<!-- tick:solo -->only")]), [])


class BoardRendering(unittest.TestCase):
    def test_renders_owner_and_hold_from_labels(self):
        pulls = [
            {
                "number": 336,
                "title": "employee types",
                "draft": False,
                "labels": [{"name": "agent:antigravity"}, {"name": "hold:author"}],
            }
        ]
        section = render_board(pulls, [], "2026-08-19T10:00:00+08:00")
        self.assertIn("#336", section)
        self.assertIn("antigravity", section)
        self.assertIn("hold:author", section)

    def test_escapes_pipes_so_a_title_cannot_break_the_table(self):
        pulls = [{"number": 1, "title": "a | b", "draft": False, "labels": []}]
        self.assertIn("a \\| b", render_board(pulls, [], "t"))

    def test_states_emptiness_rather_than_rendering_an_empty_table(self):
        section = render_board([], [], "t")
        self.assertIn("None open.", section)

    def test_always_delimited(self):
        section = render_board([], [], "t")
        self.assertTrue(section.startswith(BOARD_BEGIN))
        self.assertTrue(section.rstrip().endswith(BOARD_END))


class Splicing(unittest.TestCase):
    def test_preserves_everything_outside_the_markers(self):
        body = (
            "# Presence board\n\nStanding instruction: do not merge on hold:author.\n\n"
            f"{BOARD_BEGIN}\nstale\n{BOARD_END}\n\nFooter that must survive.\n"
        )
        spliced = splice_board(body, f"{BOARD_BEGIN}\nfresh\n{BOARD_END}")

        self.assertIn("Standing instruction", spliced)
        self.assertIn("Footer that must survive.", spliced)
        self.assertIn("fresh", spliced)
        self.assertNotIn("stale", spliced)

    def test_appends_when_no_markers_exist_yet(self):
        spliced = splice_board("Existing preamble.", f"{BOARD_BEGIN}\nnew\n{BOARD_END}")
        self.assertTrue(spliced.startswith("Existing preamble."))
        self.assertIn("new", spliced)

    def test_handles_an_empty_body(self):
        spliced = splice_board("", f"{BOARD_BEGIN}\nnew\n{BOARD_END}")
        self.assertTrue(spliced.startswith(BOARD_BEGIN))

    def test_is_idempotent(self):
        section = f"{BOARD_BEGIN}\nsame\n{BOARD_END}"
        once = splice_board("Preamble.\n", section)
        twice = splice_board(once, section)
        self.assertEqual(once, twice)

    def test_ignores_a_dangling_end_marker(self):
        # An end marker with no beginning must not truncate the body.
        body = f"Preamble.\n{BOARD_END}\nTail.\n"
        spliced = splice_board(body, f"{BOARD_BEGIN}\nnew\n{BOARD_END}")
        self.assertIn("Preamble.", spliced)
        self.assertIn("Tail.", spliced)


if __name__ == "__main__":
    unittest.main()
