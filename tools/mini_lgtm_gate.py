#!/usr/bin/env python3
"""Set the `Mini LGTM` commit status on a pull request's head commit.

    REPO=owner/name PR=123 python3 tools/mini_lgtm_gate.py [--dry-run]

Every PR here is opened from the repository owner's account, and GitHub won't
let an account APPROVE its own PR, so Mini signs off with a PR review left as a
*Comment* whose body starts with "Mini LGTM" (bold is fine: "**Mini LGTM** ...").
This turns that convention into a status that branch protection can require:

  success  the latest Mini review is an LGTM, on the head commit, or on an
           earlier commit whose net change is the same as head's (the branch was
           only rebased / updated from master, no change of its own)
  pending  no Mini review yet, or the branch changed after the LGTM
  failure  the latest Mini review is not an LGTM ("Mini: changes needed", ...)

A "Mini review" is any non-dismissed review by an OWNER / MEMBER / COLLABORATOR
whose body starts with "Mini". Dismissing the review withdraws it.

Needs `gh` (GH_TOKEN with statuses:write) and a full clone (fetch-depth 0).
"""

import hashlib
import json
import os
import re
import subprocess
import sys

CONTEXT = "Mini LGTM"
TRUSTED = {"OWNER", "MEMBER", "COLLABORATOR"}
MINI = re.compile(r"^\W*mini\b", re.I)
LGTM = re.compile(r"^\W*mini\W+lgtm\b", re.I)


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


def decide(reviews, head, base_ref):
    mini = [
        review
        for review in reviews
        if review.get("state") != "DISMISSED"
        and review.get("author_association") in TRUSTED
        and MINI.match(review.get("body") or "")
    ]
    if not mini:
        return "pending", "Waiting for Mini's review (a PR review starting \"Mini LGTM\")"
    latest = max(mini, key=lambda review: review.get("submitted_at") or "")
    reviewed = latest.get("commit_id") or ""
    short = reviewed[:7]
    if not LGTM.match(latest.get("body") or ""):
        return "failure", f"Latest Mini review ({short}) is not an LGTM"
    if reviewed == head:
        return "success", f"Mini LGTM on {short}"
    then, now = fingerprint(reviewed, base_ref), fingerprint(head, base_ref)
    if then and then == now:
        return "success", f"Mini LGTM on {short}; head has the same changes (rebased/updated)"
    return "pending", f"Changed since Mini LGTM on {short}; needs a fresh LGTM on {head[:7]}"


def main():
    repo, number = os.environ["REPO"], os.environ["PR"]
    pull = json.loads(run("gh", "api", f"repos/{repo}/pulls/{number}"))
    head, base_ref = pull["head"]["sha"], pull["base"]["ref"]
    reviews = gh_json_lines(f"repos/{repo}/pulls/{number}/reviews?per_page=100")
    state, description = decide(reviews, head, base_ref)
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


if __name__ == "__main__":
    sys.exit(main())
