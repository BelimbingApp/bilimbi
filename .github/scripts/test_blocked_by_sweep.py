import unittest

from blocked_by_sweep import (
    BLOCKED_LABEL,
    READY_LABEL,
    comment_marker,
    parse_blockers,
    transition_for,
)


class BlockedBySweepTest(unittest.TestCase):
    def test_parses_one_or_more_comma_separated_blockers(self):
        self.assertEqual(parse_blockers("Blocked-By: #131, #132, #131"), (131, 132))

    def test_rejects_missing_or_malformed_header(self):
        self.assertEqual(parse_blockers("blocked on #131"), ())
        self.assertEqual(parse_blockers("Blocked-By: #131 and #132"), ())

    def test_leaves_open_blockers_untouched(self):
        issue = {"body": "Blocked-By: #131", "labels": [{"name": BLOCKED_LABEL}]}
        self.assertIsNone(transition_for(issue, {131: "open"}))

    def test_marks_ready_and_comments_when_all_blockers_are_closed(self):
        issue = {
            "body": "Blocked-By: #131, #132",
            "labels": [{"name": BLOCKED_LABEL}, {"name": "stage:S3"}],
        }
        transition = transition_for(issue, {131: "closed", 132: "closed"}, [])

        self.assertEqual(transition.labels, ("stage:S3", READY_LABEL))
        self.assertIn("#131, #132", transition.comment)

    def test_existing_sweep_comment_makes_transition_idempotent(self):
        blockers = (131, 132)
        issue = {
            "body": "Blocked-By: #131, #132",
            "labels": [{"name": BLOCKED_LABEL}],
        }
        transition = transition_for(
            issue,
            {131: "closed", 132: "closed"},
            [f"previous result {comment_marker(blockers)}"],
        )

        self.assertEqual(transition.labels, (READY_LABEL,))
        self.assertIsNone(transition.comment)

    def test_pull_request_objects_are_not_swept(self):
        from blocked_by_sweep import sweep

        class FakeAPI:
            def open_blocked_issues(self):
                return [{"number": 201, "pull_request": {}, "labels": []}]

        self.assertEqual(sweep(FakeAPI()), 0)

    def test_sweep_comments_and_relabels_only_after_all_blockers_close(self):
        from blocked_by_sweep import sweep

        class FakeAPI:
            def __init__(self):
                self.issue = {
                    "number": 199,
                    "body": "Blocked-By: #131, #132",
                    "labels": [{"name": BLOCKED_LABEL}],
                }
                self.comments_seen = []
                self.labels_written = None

            def open_blocked_issues(self):
                return [self.issue]

            def issue_state(self, number):
                return {131: "closed", 132: "closed"}[number]

            def comments(self, number):
                return self.comments_seen

            def add_comment(self, number, body):
                self.comments_seen.append(body)

            def replace_labels(self, number, labels):
                self.labels_written = labels

        api = FakeAPI()

        self.assertEqual(sweep(api), 1)
        self.assertEqual(api.labels_written, (READY_LABEL,))
        self.assertIn("#131, #132", api.comments_seen[0])


if __name__ == "__main__":
    unittest.main()
