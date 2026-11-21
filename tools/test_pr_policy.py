import unittest

from pr_policy import check


def pull(ref, title="", body=""):
    return {"head": {"ref": ref}, "title": title, "body": body}


class PolicyTests(unittest.TestCase):
    def test_feature_branch_needs_no_ticket(self):
        errors, _ = check(pull("feature/release", "Something"), lambda n: None)
        self.assertEqual(errors, [])

    def test_non_feature_branch_fails(self):
        errors, _ = check(pull("fix/thing", "Something"), lambda n: None)
        self.assertEqual(len(errors), 1)

    def test_stacked_on_unmerged_pr_fails(self):
        errors, _ = check(pull("feature/a", body="Depends on #5"), lambda n: {"state": "open", "merged_at": None})
        self.assertEqual(len(errors), 1)

    def test_stacked_on_merged_pr_passes(self):
        errors, notes = check(pull("feature/a", body="Depends on #5"), lambda n: {"state": "closed", "merged_at": "x"})
        self.assertEqual(errors, [])
        self.assertEqual(notes, ["#5 is merged."])


if __name__ == "__main__":
    unittest.main()
