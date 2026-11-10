import unittest

from pr_policy import check


def pull(ref, title="", body=""):
    return {"head": {"ref": ref}, "title": title, "body": body}


class TicketKeyTests(unittest.TestCase):
    def errors(self, ref, title=""):
        return check(pull(ref, title), lambda n: None)[0]

    def test_linear_key_in_branch(self):
        self.assertEqual(self.errors("feature/fox-12-thing"), [])

    def test_plan_key_in_branch(self):
        self.assertEqual(self.errors("feature/twaq-1-release-3.1.6"), [])

    def test_plan_key_in_title(self):
        self.assertEqual(self.errors("feature/release", "TWAQ-7: Something"), [])

    def test_no_key_fails(self):
        self.assertEqual(len(self.errors("feature/release", "Something")), 1)

    def test_other_key_fails(self):
        self.assertEqual(len(self.errors("feature/abc-1-thing", "ABC-1: Something")), 1)


if __name__ == "__main__":
    unittest.main()
