#!/usr/bin/env python3
"""Set the `Mini LGTM` commit status on a pull request's head commit.

    REPO=owner/name PR=123 python3 tools/mini_lgtm_gate.py [--dry-run]

Every PR here is opened from the repository owner's account, and GitHub won't
let that account APPROVE its own PR. Another agent's review takes that place.
The job sets the `Mini LGTM` status on the head commit:

  success  the latest agent review covers the head commit, or an earlier
           commit whose net change is the same as head's (the branch was only
           rebased / updated from master, no change of its own)
  pending  no agent review yet, or the branch changed after the review

An agent review is a non-dismissed pull request review, or a pull request
comment, with a non-empty body that starts with the agent's name: Grok,
Claude, Codex, Cursor, Orca, or Mini. Bold markers are fine ("**Grok review**",
"**Mini LGTM**"). A bot counts when its body starts that way; a person counts
only with owner, member, or collaborator access, so a stranger can't turn the
status green by writing "Grok review". A comment has no commit of its own: it
covers the head only when it was written at or after that commit.

Needs `gh` (GH_TOKEN with statuses:write) and a full clone (fetch-depth 0).
`python3 tools/mini_lgtm_gate.py --self-test` checks the decision table.
"""

import hashlib
import json
import os
import re
import subprocess
import sys

CONTEXT = "Mini LGTM"
TRUSTED = {"OWNER", "MEMBER", "COLLABORATOR"}
AGENT = re.compile(r"^\W*(grok|claude|codex|cursor|orca|mini)\b", re.I)


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


def agent_name(item):
    match = AGENT.match(item.get("body") or "")
    if match:
        return match.group(1).capitalize()
    user = item.get("user") or {}
    return user.get("login") or "agent"


def is_agent_review(item):
    """A review or comment from Grok, Claude, Codex, Cursor, Orca, or Mini."""
    if item.get("state") == "DISMISSED":
        return False
    body = item.get("body") or ""
    if not body.strip() or not AGENT.match(body):
        return False
    user = item.get("user") or {}
    login = user.get("login") or ""
    if user.get("type") == "Bot" or login.endswith("[bot]"):
        return True
    return item.get("author_association") in TRUSTED


def covers(item, head, head_time, base_ref, finger):
    reviewed = item.get("commit_id") or ""
    if not reviewed:
        # A PR comment is not tied to a commit. It covers this head only when
        # it was written after the head commit existed.
        created = item.get("at") or ""
        return bool(head_time) and created >= head_time
    if reviewed == head:
        return True
    then, now = finger(reviewed, base_ref), finger(head, base_ref)
    return bool(then) and then == now


def decide(items, head, head_time, base_ref, finger=fingerprint):
    agents = [item for item in items if is_agent_review(item)]
    if not agents:
        return "pending", "Waiting for a review from another agent (Grok, Claude, Codex, Cursor, Orca, or Mini)"
    latest = max(agents, key=lambda item: item.get("at") or "")
    name = agent_name(latest)
    reviewed = latest.get("commit_id") or ""
    short = (reviewed or head)[:7]
    if covers(latest, head, head_time, base_ref, finger):
        if reviewed and reviewed != head:
            return "success", f"{name} review on {reviewed[:7]}; head has the same changes (rebased/updated)"
        return "success", f"{name} review on {short}"
    if reviewed:
        return "pending", f"Changed since {name} review on {reviewed[:7]}; needs a fresh review on {head[:7]}"
    return "pending", f"{name} review is older than {head[:7]}; needs a fresh review"


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
        ("grok on head", [item("Grok review\n\nlooks fine")], "success"),
        ("mini lgtm still counts", [item("**Mini LGTM**\n\nship it")], "success"),
        ("mini changes needed still counts", [item("**Mini** changes needed")], "success"),
        ("empty review", [item("   ")], "pending"),
        ("owner note without an agent name", [item("Checked against FOX-47")], "pending"),
        ("stranger", [item("Grok review", author_association="NONE", user=stranger)], "pending"),
        ("bot claude", [item("**Claude finished** the review", user=bot, author_association="NONE")], "success"),
        ("actions bot noise", [item("<!-- vulnerability-checks -->\nno secrets", user={"login": "github-actions[bot]", "type": "Bot"}, author_association="NONE")], "pending"),
        ("dismissed", [item("Grok review", state="DISMISSED")], "pending"),
        ("same diff after rebase", [item("Codex review", commit_id="old")], "success"),
        ("new commits since review", [item("Orca review", commit_id="other")], "pending"),
        ("comment after the head commit", [item("Cursor review", commit_id="", at="2026-11-02T12:00:00Z")], "success"),
        ("comment before the head commit", [item("Grok review", commit_id="", at="2026-11-02T10:00:00Z")], "pending"),
    ]
    failed = 0
    for name, items, want in cases:
        state, description = decide(items, head, "2026-11-02T11:00:00Z", "master", same)
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
