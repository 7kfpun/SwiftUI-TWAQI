"""Tests for public_text_check.py: python3 -m unittest discover -s tools -p 'test_public_text_check.py'"""

import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import public_text_check as ptc  # noqa: E402


def kinds(text, **kw):
    return [(f.kind, f.text) for f in ptc.check_text(text, "x", **kw)]


class CheckText(unittest.TestCase):
    def test_website_hosts_are_fine(self):
        self.assertEqual(kinds("see https://taiwanair.wahthefox.com/privacy.html and kf-twaqi.web.app"), [])
        self.assertEqual(kinds("kf-nihongo.web.app"), [])

    def test_legacy_alias_domain_is_flagged(self):
        # Only the three sites in CLAUDE.md are allowed; a sibling wahthefox.com name is not.
        self.assertEqual(kinds("see japanesedaily.wahthefox.com"), [("host", "japanesedaily.wahthefox.com")])

    def test_other_hosts_are_flagged(self):
        for host in (
            "api-x.wahthefox.com",
            "x.y.wahthefox.com",
            "w.someone.workers.dev",
            "svc-1.asia-east1.run.app",
            "abc123.execute-api.us-west-2.amazonaws.com",
            "proj-x.appspot.com",
        ):
            self.assertEqual(kinds(f"call https://{host}/v1"), [("host", host)], host)

    def test_hosts_allowed_in_files_that_need_them(self):
        self.assertEqual(kinds('"DIRECTUS_URL": "https://api-x.wahthefox.com"', hosts_allowed=True), [])
        self.assertEqual(kinds("192.0.2.7", hosts_allowed=True), [("ip", "192.0.2.7")])

    def test_ips_and_ranges(self):
        self.assertEqual(kinds("allowed 203.0.113.0/24 and 198.51.100.9"), [("ip", "203.0.113.0/24"), ("ip", "198.51.100.9")])
        self.assertEqual(kinds("bind 0.0.0.0:8080, local 127.0.0.1"), [])
        self.assertEqual(kinds("version 3.1.4, iOS 27.2, 1.2.3"), [])

    def test_emails(self):
        self.assertEqual(kinds("write to info@dllm.io"), [])
        self.assertEqual(kinds("write to info@wahthefox.com"), [])
        self.assertEqual(kinds("Co-Authored-By: Claude <noreply@anthropic.com>"), [])
        self.assertEqual(kinds("icon@2x.png"), [])
        self.assertEqual(kinds("owner is someone@gmail.com"), [("email", "someone@gmail.com")])
        self.assertEqual(kinds("sa@kf-proj.iam.gserviceaccount.com"), [("email", "sa@kf-proj.iam.gserviceaccount.com")])

    def test_posture_wording(self):
        self.assertEqual(sorted(kinds("narrowed from 0.0.0.0/0 to ...")), [("ip", "0.0.0.0/0"), ("posture", "0.0.0.0/0")])
        self.assertEqual(kinds("the instance's authorized networks"), [("posture", "authorized networks")])
        self.assertEqual(kinds("it was open to the internet"), [("posture", "open to the internet")])
        self.assertEqual(kinds("an allow-list of query params"), [])

    def test_line_numbers(self):
        f = ptc.check_text("ok\napi-x.wahthefox.com", "README.md", line_offset=10)
        self.assertEqual((f[0].line, f[0].annotation()[:30]), (12, "::error file=README.md,line=12"))


class CheckPr(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "t")
        self.write("README.md", "hello\n")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "base")
        self.base = self.git("rev-parse", "HEAD").strip()

    def tearDown(self):
        self.dir.cleanup()

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.dir.name, check=True, capture_output=True, text=True).stdout

    def write(self, path, text):
        full = os.path.join(self.dir.name, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as f:
            f.write(text)

    def run_check(self, title="t", body="b"):
        head = self.git("rev-parse", "HEAD").strip()
        cwd = os.getcwd()
        os.chdir(self.dir.name)
        try:
            return [(f.where, f.kind, f.text) for f in ptc.check_pr(self.base, head, title, body)]
        finally:
            os.chdir(cwd)

    def test_added_doc_line_title_body_and_commit_message(self):
        self.write("README.md", "hello\nsee api-x.wahthefox.com\n")
        self.write("workers/x/wrangler.jsonc", '{ "url": "https://api-x.wahthefox.com" }\n')
        self.git("add", ".")
        self.git("commit", "-q", "-m", "add 192.0.2.3 note")
        found = self.run_check(title="FOX-1: route on x.y.wahthefox.com", body="0.0.0.0/0 removed")
        self.assertIn(("README.md", "host", "api-x.wahthefox.com"), found)
        self.assertIn(("PR title", "host", "x.y.wahthefox.com"), found)
        self.assertIn(("PR description", "posture", "0.0.0.0/0"), found)
        self.assertTrue(any(w.startswith("commit ") and k == "ip" for w, k, _ in found), found)
        self.assertFalse(any(w.endswith("wrangler.jsonc") for w, _, _ in found), "config may name hosts")

    def test_existing_lines_are_not_rechecked(self):
        self.git("commit", "-q", "--allow-empty", "-m", "nothing")
        self.assertEqual(self.run_check(), [])


if __name__ == "__main__":
    unittest.main()
