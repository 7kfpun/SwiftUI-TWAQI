import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import needs_human as nh  # noqa: E402


def f(name, a=0, d=0):
    return {"filename": name, "additions": a, "deletions": d}


def pr(labels, draft=False, state="open"):
    return {"labels": [{"name": l} for l in labels], "draft": draft, "state": state,
            "head": {"sha": "abcdef1234"}, "number": 7, "title": "T", "html_url": "https://github.com/o/r/pull/7"}


class ReadTime(unittest.TestCase):
    def test_minimum(self):
        self.assertEqual(nh.read_minutes([f("a.swift", 3)])[0], 5)

    def test_rounds_up(self):
        self.assertEqual(nh.read_minutes([f("a.swift", 450)])[0], 60)
        self.assertEqual(nh.read_minutes([f("a.swift", 451)])[0], 61)

    def test_ignores_lockfiles_and_generated(self):
        files = [f("ios/Podfile.lock", 5000), f("ios/Package.resolved", 900), f("x/TWAQI.xcodeproj/project.pbxproj", 800),
                 f("a/foo.generated.swift", 700), f("a.swift", 90, 90)]
        self.assertEqual(nh.read_minutes(files), (24, 180))

    def test_format(self):
        self.assertEqual(nh.format_minutes(45), "45 min")
        self.assertEqual(nh.format_minutes(120), "2 h")
        self.assertEqual(nh.format_minutes(75), "1 h 15 min")


class Risky(unittest.TestCase):
    def test_paths(self):
        r = nh.risky_paths([f("workers/a/src/i.ts"), f("ios/TWAQI/Utils/DirectusPushMirror.swift"),
                            f("ios/TWAQI/Views/PurchaseView.swift"), f(".github/workflows/x.yml"), f("README.md")])
        self.assertEqual(len(r), 4)
        self.assertEqual(nh.risky_paths([f("README.md")]), [])


class Bullets(unittest.TestCase):
    def item(self, body, user="Grok", t="2026-01-01T00:00:00Z", assoc="OWNER"):
        return {"user": user, "created": t, "body": body, "assoc": assoc}

    def test_copies_bullets(self):
        body = "**Grok LGTM** (head abc)\n\nrisk: high\n\nHuman check:\n- Read the retry path\n- Try alerts off\n\nOther text\n- not copied"
        self.assertEqual(nh.human_checks([self.item(body)]), (["Read the retry path", "Try alerts off"], 0))

    def test_filters_public_details(self):
        body = ("**Grok LGTM**\nHuman check:\n- Open " + ".".join(["10", "1", "2", "3"]) + " to the world\n- Call foo." + "workers" + ".dev\n- ping admin" + "@corp" + ".io\n"
                "- key ghp_abcdefghijklmnop1234\n- Fine one @user")
        self.assertEqual(nh.human_checks([self.item(body)]), (["Fine one @​user"], 4))

    def test_claude_bot_and_changes_needed(self):
        ok = self.item("**Grok LGTM**\nHuman check:\n- a", t="2026-01-01T00:00:00Z")
        bot = self.item("LGTM\nHuman check:\n- b", user="claude[bot]", t="2026-01-02T00:00:00Z")
        self.assertEqual(nh.human_checks([ok, bot]), (["a"], 0))
        no = self.item("**Codex — changes needed**", t="2026-01-03T00:00:00Z")
        self.assertEqual(nh.human_checks([ok, no]), ([], 0))
        again = self.item("**Grok LGTM**\nHuman check: only this", t="2026-01-04T00:00:00Z")
        self.assertEqual(nh.human_checks([ok, no, again]), (["only this"], 0))

    def test_path_bullet_kept(self):
        body = "**Grok LGTM**\nHuman check:\n- Retry path in `ios/TWAQI/Utils/DirectusPushMirror.swift`"
        self.assertEqual(nh.human_checks([self.item(body)])[1], 0)

    def test_stranger_ignored(self):
        ok = self.item("**Grok LGTM**\nHuman check:\n- real", t="2026-01-01T00:00:00Z")
        fake = self.item("**X LGTM**\nHuman check:\n- fake", user="eve", assoc="NONE", t="2026-01-02T00:00:00Z")
        cancel = self.item("**X — changes needed**", user="eve", assoc="CONTRIBUTOR", t="2026-01-03T00:00:00Z")
        self.assertEqual(nh.human_checks([ok, fake, cancel]), (["real"], 0))

    def test_multi_word_names(self):
        ok = self.item("**Claude Code LGTM**\nHuman check:\n- a", t="2026-01-01T00:00:00Z")
        no = self.item("**Claude Code — changes needed**", t="2026-01-02T00:00:00Z")
        self.assertEqual(nh.human_checks([ok]), (["a"], 0))
        self.assertEqual(nh.human_checks([ok, no]), ([], 0))
        self.assertEqual(nh.human_checks([self.item("Not LGTM\nHuman check:\n- a")]), ([], 0))

    def test_no_lgtm(self):
        self.assertEqual(nh.human_checks([self.item("Human check:\n- a")]), ([], 0))


class Comment(unittest.TestCase):
    def test_conditions(self):
        self.assertTrue(nh.needs_eyes(pr(["merge-risk:high"])))
        self.assertTrue(nh.needs_eyes(pr(["no-auto-merge"])))
        self.assertFalse(nh.needs_eyes(pr(["merge-risk:low"])))
        self.assertFalse(nh.needs_eyes(pr(["needs-human"], draft=True)))
        self.assertFalse(nh.needs_eyes(pr(["needs-human"], state="closed")))
        stacked = pr(["needs-human"])
        stacked["base"] = {"ref": "feature/other"}
        self.assertFalse(nh.needs_eyes(stacked))

    def test_body(self):
        body = nh.build_comment(pr(["merge-risk:high", "needs-human"]), [f("workers/a.ts", 100)], ["Check X"])
        self.assertTrue(body.startswith(nh.MARKER))
        for s in ("## Needs your eyes", "`merge-risk:high`, `needs-human`", "~14 min", "- Check X", "workers/"):
            self.assertIn(s, body)
        self.assertIn("none from the reviewer", nh.build_comment(pr(["needs-human"]), [], []))
        withheld = nh.build_comment(pr(["needs-human"]), [], [], 2)
        self.assertIn("2 bullet(s) withheld", withheld)
        self.assertNotIn("none from the reviewer", withheld)


if __name__ == "__main__":
    unittest.main()
