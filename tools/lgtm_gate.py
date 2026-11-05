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
stranger can't turn the status green by writing "LGTM".

A rebase or "Update branch" (a merge from master) keeps an LGTM. "Same net
change" compares the PR's own added and removed lines per file against the
merge base, ignoring where master was: hunk positions, blob ids and the
unchanged context lines around each hunk, which move whenever master edits
nearby. Resolving a conflict or any edit of the branch's own changes the net
change and needs a fresh LGTM.

A review is tied to the commit it was left on. A comment has no commit of its
own: one with a "(head <sha>)" note is tied to that commit, so it survives a
rebase like a review does; one without a note covers the head only when it was
written at or after that commit.

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
# Bases whose PRs get the status: master, and the Android integration branch
# that Android ticket PRs target until it merges to master itself (FOX-52, #77).
GATED_BASES = ("master", "feature/fox-52-android-project-setup")
TRUSTED = {"OWNER", "MEMBER", "COLLABORATOR"}
# First line: an optional one-word reviewer name, then the verdict.
# Nothing may follow LGTM on that line except emphasis, "." "!" ":" or a
# "(head <sha>)" note, so "LGTM?" and "LGTM, but fix X" don't pass.
# The "(head <sha>)" note a reviewer adds to the verdict line.
HEAD_NOTE = re.compile(r"\(head\s+([0-9a-f]{7,40})\)", re.I)
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


def has_commit(sha):
    return subprocess.run(["git", "cat-file", "-e", f"{sha}^{{commit}}"], capture_output=True).returncode == 0


def resolve_commit(sha):
    """Full sha of `sha` (which may be a short one from a "(head <sha>)" note),
    fetched when a rebase left it off every branch. None if it can't be found."""
    if not has_commit(sha) and len(sha) < 40 and os.environ.get("REPO"):
        # A short sha can't be fetched; GitHub resolves it to the full one.
        sha = run("gh", "api", f"repos/{os.environ['REPO']}/commits/{sha}", "--jq", ".sha", check=False).strip() or sha
    if not has_commit(sha):
        subprocess.run(["git", "fetch", "--quiet", "origin", sha], capture_output=True)
    if not has_commit(sha):
        return None
    return run("git", "rev-parse", f"{sha}^{{commit}}", check=False).strip() or None


def normalize_diff(diff):
    """The PR's own changes in `diff`: file headers and added/removed lines.
    Drops what moves when master changes around the PR: blob ids, hunk
    positions, and the unchanged context lines (" ...") inside hunks."""
    normalized = []
    for line in diff.splitlines():
        if line.startswith("index "):
            continue  # blob ids move when master changes the same file elsewhere
        if line.startswith("@@"):
            continue  # line numbers move when master changes earlier lines
        if line.startswith(" "):
            continue  # context moves when master edits lines next to the PR's
        normalized.append(line)
    return "\n".join(normalized)


def fingerprint(sha, base_ref):
    """Hash of the PR's net change at `sha`, ignoring where master was."""
    sha = resolve_commit(sha)
    if not sha:
        return None
    base = run("git", "merge-base", f"origin/{base_ref}", sha, check=False).strip()
    if not base:
        return None
    diff = run("git", "diff", "--no-color", "--no-ext-diff", "--binary", base, sha, check=False)
    return hashlib.sha256(normalize_diff(diff).encode()).hexdigest()


def first_line(item):
    return (item.get("body") or "").strip().splitlines()[0] if (item.get("body") or "").strip() else ""


def reviewed_commit(item):
    """The commit a verdict is about: a review's own commit, or the
    "(head <sha>)" note on a comment's first line. "" when there is neither."""
    if item.get("commit_id"):
        return item["commit_id"]
    note = HEAD_NOTE.search(first_line(item))
    return note.group(1).lower() if note else ""


def is_commit(sha, head):
    """`sha` (full, or short from a note) names `head`."""
    return bool(sha) and len(sha) >= 7 and head.lower().startswith(sha.lower())


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
    reviewed = reviewed_commit(item)
    if not reviewed:
        # A PR comment without a "(head <sha>)" note is not tied to a commit.
        # It covers this head only when it was written after the head commit existed.
        created, committed = parse_time(item.get("at")), parse_time(head_time)
        return bool(created and committed) and created >= committed
    if is_commit(reviewed, head):
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
    reviewed = reviewed_commit(latest)
    short = (reviewed or head)[:7]
    if kind == "changes":
        return "pending", f"{name}: changes needed on {short}; needs a fresh LGTM"
    if covers(latest, head, head_time, base_ref, finger):
        if reviewed and not is_commit(reviewed, head):
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
    if pull["base"]["ref"] not in GATED_BASES:
        print(f"{CONTEXT}: skip — base is {pull['base']['ref']}, not one of {', '.join(GATED_BASES)}")
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

    # "old" and "1234567" stand for earlier commits with head's net change
    # (rebased / updated from master); anything else has changes of its own.
    def same(reviewed, base):
        return "same" if reviewed in ("old", "1234567", head) or is_commit(reviewed, head) else "other"

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
        ("comment noting the head, written before it", [item("**Grok LGTM** (head abcdef1)", commit_id="", at="2026-11-02T10:00:00Z")], "success"),
        ("comment noting a rebased-away commit with the same changes",
         [item("**Codex LGTM** (head 1234567)", commit_id="", at="2026-11-02T10:00:00Z")], "success"),
        ("comment noting a commit with other changes, written after head",
         [item("**Codex LGTM** (head 7654321)", commit_id="", at="2026-11-02T12:00:00Z")], "pending"),
        ("review keeps its own commit over a note", [item("**Grok LGTM** (head 1234567)", commit_id="other")], "pending"),
        ("changes needed on a rebased-away commit still vetoes",
         [item("**Grok LGTM**", at="2026-11-02T12:00:00Z"), item("**Codex — changes needed** (head 1234567)", commit_id="", at="2026-11-02T12:05:00Z")], "pending"),
    ]
    failed = 0

    # The fingerprint's normalization: what master moves around the PR is
    # ignored, the PR's own added/removed lines are not.
    reviewed_diff = (
        "diff --git a/f.swift b/f.swift\nindex 1111111..2222222 100644\n--- a/f.swift\n+++ b/f.swift\n"
        "@@ -10,7 +10,7 @@ struct A {\n     let a = 1\n-    let b = 2\n+    let b = 3\n     let c = 4\n"
    )
    diff_cases = [
        ("rebased: new blob ids, hunk position and context", (
            "diff --git a/f.swift b/f.swift\nindex 3333333..4444444 100644\n--- a/f.swift\n+++ b/f.swift\n"
            "@@ -14,7 +14,7 @@ struct A {\n     let a = 10\n-    let b = 2\n+    let b = 3\n     let c = 40\n"
        ), True),
        ("an added line of its own", reviewed_diff + "+    let d = 5\n", False),
        ("a different change", reviewed_diff.replace("+    let b = 3", "+    let b = 4"), False),
        ("another file touched", reviewed_diff + "diff --git a/g.swift b/g.swift\n--- a/g.swift\n+++ b/g.swift\n@@ -1 +1 @@\n-x\n+y\n", False),
    ]
    for name, other, want_same in diff_cases:
        got_same = normalize_diff(other) == normalize_diff(reviewed_diff)
        if got_same != want_same:
            failed += 1
            print(f"FAIL fingerprint {name}: same={got_same}, want {want_same}")
        else:
            print(f"ok   fingerprint {name}: same={got_same}")

    for name, items, want, *rest in cases:
        head_time = rest[0] if rest else "2026-11-02T11:00:00Z"
        state, description = decide(items, head, head_time, "master", same)
        if state != want:
            failed += 1
            print(f"FAIL {name}: got {state} ({description}), want {want}")
        else:
            print(f"ok   {name}: {state}")

    # Same verdicts on a PR into the Android integration branch: decide() takes
    # the PR's base ref and passes it to the fingerprint.
    seen_bases = []

    def same_on_base(reviewed, base):
        seen_bases.append(base)
        return same(reviewed, base)

    android_base = "feature/fox-52-android-project-setup"
    base_cases = [
        ("integration base: lgtm after an update", [item("Codex LGTM", commit_id="old")], "success"),
        ("integration base: new commits since lgtm", [item("Orca LGTM", commit_id="other")], "pending"),
    ]
    for name, items, want in base_cases:
        state, description = decide(items, head, "2026-11-02T11:00:00Z", android_base, same_on_base)
        if state != want or (seen_bases and set(seen_bases) != {android_base}):
            failed += 1
            print(f"FAIL {name}: got {state} ({description}) on bases {sorted(set(seen_bases))}, want {want}")
        else:
            print(f"ok   {name}: {state}")
    gate_cases = [("master", True), (android_base, True), ("feature/fox-99-other", False)]
    for base, want_gated in gate_cases:
        if (base in GATED_BASES) != want_gated:
            failed += 1
            print(f"FAIL gated base {base}: want {want_gated}")
        else:
            print(f"ok   gated base {base}: {want_gated}")
    if failed:
        print(f"{failed} failed")
        return 1
    print(f"{len(cases) + len(diff_cases) + len(base_cases) + len(gate_cases)} passed")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    sys.exit(main())
