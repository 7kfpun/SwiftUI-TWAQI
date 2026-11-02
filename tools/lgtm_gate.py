#!/usr/bin/env python3
"""Set the `LGTM` commit status on a pull request's head commit.

    REPO=owner/name PR=123 python3 tools/lgtm_gate.py [--dry-run]

Every PR here is opened from the repository owner's account, and GitHub won't
let that account APPROVE its own PR. A reviewer's LGTM takes that place. The
job sets the `LGTM` status on the head commit:

  success  the latest verdict is an LGTM that covers the head commit, or an
           earlier commit whose net change is the same as head's (the branch
           was only rebased / updated from master, no change of its own)
  pending  no LGTM yet, a later "changes needed" overrides it, or the branch
           changed after it

The gate doesn't know or care which agent reviewed: agents come and go. A
verdict is a non-dismissed pull request review, or a pull request comment,
whose first line is "LGTM" or "changes needed", optionally after one word naming
the reviewer. Bold and punctuation are fine:

  LGTM     "**Grok LGTM** (head abc1234)", "Copilot LGTM", "**LGTM**"
  changes  "**Codex — changes needed** (head abc1234)", "Changes requested",
           or a review with GitHub's CHANGES_REQUESTED state

Nothing may follow LGTM on its line but punctuation or "(head <sha>)", so
"LGTM?" and "LGTM, but fix X" don't pass. A negating or qualifying word in the
name slot ("Not LGTM", "Never LGTM", "Almost LGTM") isn't a name, and
"Grok review" alone is no verdict. A bot counts,
except claude[bot]: the Claude Code Review workflow is advisory, and its
progress comment ("**Claude Code is working…**") appears before any review is
done. A person counts only with owner, member, or collaborator access, so a
stranger can't turn the status green by writing "LGTM". A comment has no commit
of its own: it covers the head only when it was written at or after that commit.

Needs `gh` (GH_TOKEN with statuses:write) and a full clone (fetch-depth 0).
`python3 tools/lgtm_gate.py --self-test` checks the decision table.
"""

import hashlib
import json
from datetime import datetime
import os
import re
import subprocess
import sys

CONTEXT = "LGTM"
TRUSTED = {"OWNER", "MEMBER", "COLLABORATOR"}
# First line: an optional one-word reviewer name, then the verdict.
# Nothing may follow LGTM on that line except emphasis, "." "!" ":" or a
# "(head <sha>)" note, so "LGTM?" and "LGTM, but fix X" don't pass.
LGTM = re.compile(
    r"^\W*(?:(?P<name>[A-Za-z][\w.-]{0,39})\W+)?LGTM\b"
    r"[\s*_~.!:]*(?:\(head\s+[0-9a-f]{7,40}\)[\s*_~.!:]*)?$",
    re.I,
)
CHANGES = re.compile(r"^\W*(?:(?P<name>[A-Za-z][\w.-]{0,39})\W+)?changes\s+(?:needed|requested)\b", re.I)
# Words that can't be a reviewer's name: they negate or qualify the verdict.
NEGATIONS = {
    "not", "no", "non", "never", "cannot", "cant", "without", "almost", "nearly",
    "zero", "nothing", "partial", "partially", "conditional", "pre", "pending",
}
# The Claude Code Review workflow's bot: advisory, not a sign-off.
EXCLUDED_BOTS = {"claude[bot]"}


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True).stdout


def gh_json_lines(endpoint):
    out = run("gh", "api", "--paginate", endpoint, "--jq", ".[]")
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def fingerprint(sha, base_ref):
    """Hash of the PR's net change at `sha`, ignoring where master was."""
    if subprocess.run(["git", "cat-file", "-e", f"{sha}^{{commit}}"], capture_output=True).returncode != 0:
        subprocess.run(["git", "fetch", "--quiet", "origin", sha], capture_output=True)
    base = run("git", "merge-base", f"origin/{base_ref}", sha, check=False).strip()
    if not base:
        return None
    diff = run("git", "diff", "--no-color", "--no-ext-diff", "--binary", base, sha, check=False)
    normalized = []
    for line in diff.splitlines():
        if line.startswith("index "):
            continue  # blob ids move when master changes the same file elsewhere
        if line.startswith("@@"):
            line = "@@"  # line numbers move when master changes earlier lines
        normalized.append(line)
    return hashlib.sha256("\n".join(normalized).encode()).hexdigest()


def first_line(item):
    return (item.get("body") or "").strip().splitlines()[0] if (item.get("body") or "").strip() else ""


def verdict(item):
    """"lgtm", "changes", or None. Only trusted people and bots (not claude[bot]) count."""
    if item.get("state") == "DISMISSED":
        return None
    user = item.get("user") or {}
    login = user.get("login") or ""
    if login in EXCLUDED_BOTS:
        return None
    is_bot = user.get("type") == "Bot" or login.endswith("[bot]")
    if not is_bot and item.get("author_association") not in TRUSTED:
        return None
    if item.get("state") == "CHANGES_REQUESTED":
        return "changes"
    line = first_line(item)
    for kind, pattern in (("changes", CHANGES), ("lgtm", LGTM)):
        match = pattern.match(line)
        if match and (match.group("name") or "").lower() not in NEGATIONS:
            return kind
    return None


def reviewer_name(item):
    line = first_line(item)
    for pattern in (CHANGES, LGTM):
        match = pattern.match(line)
        if match and match.group("name") and match.group("name").lower() not in {"changes", *NEGATIONS}:
            return match.group("name").capitalize()
    user = item.get("user") or {}
    return user.get("login") or "reviewer"


def parse_time(value):
    """An ISO 8601 time as an aware datetime, or None. Git gives the committer's
    offset (+08:00), GitHub gives UTC (Z), so they can't be compared as text."""
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def covers(item, head, head_time, base_ref, finger):
    reviewed = item.get("commit_id") or ""
    if not reviewed:
        # A PR comment is not tied to a commit. It covers this head only when
        # it was written after the head commit existed.
        created, committed = parse_time(item.get("at")), parse_time(head_time)
        return bool(created and committed) and created >= committed
    if reviewed == head:
        return True
    then, now = finger(reviewed, base_ref), finger(head, base_ref)
    return bool(then) and then == now


def decide(items, head, head_time, base_ref, finger=fingerprint):
    verdicts = [(item, verdict(item)) for item in items]
    verdicts = [(item, kind) for item, kind in verdicts if kind]
    if not verdicts:
        return "pending", "Waiting for a reviewer's LGTM (\"**<Name> LGTM**\")"
    latest, kind = max(verdicts, key=lambda pair: pair[0].get("at") or "")
    name = reviewer_name(latest)
    reviewed = latest.get("commit_id") or ""
    short = (reviewed or head)[:7]
    if kind == "changes":
        return "pending", f"{name}: changes needed on {short}; needs a fresh LGTM"
    if covers(latest, head, head_time, base_ref, finger):
        if reviewed and reviewed != head:
            return "success", f"{name} LGTM on {reviewed[:7]}; head has the same changes (rebased/updated)"
        return "success", f"{name} LGTM on {short}"
    if reviewed:
        return "pending", f"Changed since {name} LGTM on {reviewed[:7]}; needs a fresh LGTM on {head[:7]}"
    return "pending", f"{name} LGTM is older than {head[:7]}; needs a fresh LGTM"


def normalize_review(review):
    return {
        "body": review.get("body") or "",
        "state": review.get("state") or "",
        "author_association": review.get("author_association") or "",
        "user": review.get("user") or {},
        "commit_id": review.get("commit_id") or "",
        "at": review.get("submitted_at") or "",
    }


def normalize_comment(comment):
    return {
        "body": comment.get("body") or "",
        "state": "",
        "author_association": comment.get("author_association") or "",
        "user": comment.get("user") or {},
        "commit_id": "",
        "at": comment.get("created_at") or "",
    }


def commit_time(sha):
    if subprocess.run(["git", "cat-file", "-e", f"{sha}^{{commit}}"], capture_output=True).returncode != 0:
        subprocess.run(["git", "fetch", "--quiet", "origin", sha], capture_output=True)
    return run("git", "log", "-1", "--format=%cI", sha, check=False).strip()


def main():
    repo, number = os.environ["REPO"], os.environ["PR"]
    pull = json.loads(run("gh", "api", f"repos/{repo}/pulls/{number}"))
    if pull["base"]["ref"] != "master":
        print(f"{CONTEXT}: skip — base is {pull['base']['ref']}, not master")
        return 0
    head, base_ref = pull["head"]["sha"], pull["base"]["ref"]
    reviews = [normalize_review(review) for review in gh_json_lines(f"repos/{repo}/pulls/{number}/reviews?per_page=100")]
    comments = [normalize_comment(comment) for comment in gh_json_lines(f"repos/{repo}/issues/{number}/comments?per_page=100")]
    state, description = decide(reviews + comments, head, commit_time(head), base_ref)
    print(f"{CONTEXT}: {state} — {description} (head {head[:7]})")
    if "--dry-run" in sys.argv:
        return 0
    run(
        "gh", "api", "--method", "POST", f"repos/{repo}/statuses/{head}",
        "-f", f"state={state}",
        "-f", f"context={CONTEXT}",
        "-f", f"description={description[:140]}",
        "-f", f"target_url={pull['html_url']}",
    )
    return 0


def self_test():
    owner = {"login": "7kfpun", "type": "User"}
    bot = {"login": "claude[bot]", "type": "Bot"}
    stranger = {"login": "someone", "type": "User"}
    head = "abcdef1234567890"

    def same(reviewed, base):
        return "same" if reviewed in ("old", head) else "other"

    def item(body, **extra):
        base = {
            "body": body,
            "state": "COMMENTED",
            "author_association": "OWNER",
            "user": owner,
            "commit_id": head,
            "at": "2026-11-02T12:00:00Z",
        }
        base.update(extra)
        return base

    cases = [
        ("no review", [], "pending"),
        ("grok lgtm on head", [item("**Grok LGTM** (head abcdef1)\n\nlooks fine")], "success"),
        ("any reviewer name", [item("**Copilot LGTM**")], "success"),
        ("a name the gate has never seen", [item("Zephyr LGTM")], "success"),
        ("bare lgtm", [item("LGTM")], "success"),
        ("lgtm with a dash", [item("**Grok — LGTM**")], "success"),
        ("not lgtm", [item("Not LGTM: the clear races")], "pending"),
        ("no lgtm", [item("No LGTM yet")], "pending"),
        ("review without a verdict", [item("**Grok review**\n\nlooks fine")], "pending"),
        ("changes needed", [item("**Codex — changes needed** (head abcdef1)")], "pending"),
        ("changes needed after an lgtm on the same head",
         [item("**Grok LGTM**", at="2026-11-02T12:00:00Z"), item("**Codex — changes needed**", at="2026-11-02T12:05:00Z")], "pending"),
        ("lgtm after changes needed", [item("**Codex — changes needed**", at="2026-11-02T12:00:00Z"), item("**Codex LGTM**", at="2026-11-02T12:05:00Z")], "success"),
        ("github changes requested state", [item("see inline comments", state="CHANGES_REQUESTED", user={"login": "cursor[bot]", "type": "Bot"}, author_association="NONE")], "pending"),
        ("lgtm later in the body only", [item("Checked FOX-36.\n\nLGTM")], "pending"),
        ("lgtm with a head note", [item("**Grok LGTM** (head abcdef1)")], "success"),
        ("lgtm with an exclamation", [item("LGTM!")], "success"),
        ("never lgtm", [item("Never LGTM")], "pending"),
        ("cannot lgtm", [item("**Cannot LGTM** (head abcdef1)")], "pending"),
        ("almost lgtm", [item("Almost LGTM")], "pending"),
        ("can't lgtm", [item("Can't LGTM this")], "pending"),
        ("lgtm question", [item("LGTM?")], "pending"),
        ("lgtm with a condition", [item("LGTM, but fix the time zone")], "pending"),
        ("zero changes needed is no veto",
         [item("**Grok LGTM**", at="2026-11-02T12:00:00Z"), item("Zero changes needed", at="2026-11-02T12:05:00Z")], "success"),
        ("owner note", [item("Grok, please fix the time zone")], "pending"),
        ("empty review", [item("   ")], "pending"),
        ("stranger", [item("LGTM", author_association="NONE", user=stranger)], "pending"),
        ("claude[bot] progress comment", [item("**Claude Code is working…**", user=bot, author_association="NONE")], "pending"),
        ("claude[bot] even with lgtm", [item("LGTM", user=bot, author_association="NONE")], "pending"),
        ("other bot lgtm", [item("**Codex LGTM**", user={"login": "codex[bot]", "type": "Bot"}, author_association="NONE")], "success"),
        ("actions bot noise", [item("<!-- vulnerability-checks -->\nno secrets", user={"login": "github-actions[bot]", "type": "Bot"}, author_association="NONE")], "pending"),
        ("dismissed", [item("Grok LGTM", state="DISMISSED")], "pending"),
        ("same diff after rebase", [item("Codex LGTM", commit_id="old")], "success"),
        ("new commits since lgtm", [item("Orca LGTM", commit_id="other")], "pending"),
        ("comment after the head commit", [item("Cursor LGTM", commit_id="", at="2026-11-02T12:00:00Z")], "success"),
        ("comment before the head commit", [item("Grok LGTM", commit_id="", at="2026-11-02T10:00:00Z")], "pending"),
        ("comment after a +08:00 head commit", [item("Grok LGTM", commit_id="", at="2026-11-02T11:00:30Z")], "success", "2026-11-02T19:00:00+08:00"),
        ("comment before a +08:00 head commit", [item("Grok LGTM", commit_id="", at="2026-11-02T10:59:59Z")], "pending", "2026-11-02T19:00:00+08:00"),
        ("unreadable head time", [item("Grok LGTM", commit_id="")], "pending", ""),
    ]
    failed = 0
    for name, items, want, *rest in cases:
        head_time = rest[0] if rest else "2026-11-02T11:00:00Z"
        state, description = decide(items, head, head_time, "master", same)
        if state != want:
            failed += 1
            print(f"FAIL {name}: got {state} ({description}), want {want}")
        else:
            print(f"ok   {name}: {state}")
    if failed:
        print(f"{failed} failed")
        return 1
    print(f"{len(cases)} passed")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    sys.exit(main())
