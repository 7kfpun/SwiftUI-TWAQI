#!/usr/bin/env python3
"""Keep the human queue short and specific (FOX-179).

A non-draft PR labelled `merge-risk:high`, `no-auto-merge` or `needs-human` waits for the
repository owner. This script keeps ONE sticky comment headed `Needs your eyes` on such a
PR (read time, risky paths touched, the reviewer's `Human check:` bullets), and removes it
when the labels are gone, the PR is a draft or closed. `queue` keeps one issue with a line
per waiting PR.

    REPO=owner/name PR=123 python3 tools/needs_human.py pr [--dry-run]
    REPO=owner/name python3 tools/needs_human.py queue [--dry-run]

Built-in token only (pull-requests, issues). Nothing from the PR is checked out or run:
the workflow runs master's copy of this file. The repo is public, so reviewer bullets are
copied only after the public-text filter drops lines naming hosts, IPs, emails, network
exposure wording or secret-looking values (docs/ci-cd-guardrails.md#public-repo-what-stays-out).
Tests: python3 -m unittest discover -s tools -p 'test_needs_human.py'
"""

from __future__ import annotations

import fnmatch
import json
import math
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from public_text_check import check_text  # noqa: E402

MARKER = "<!-- needs-human-sticky -->"
QUEUE_MARKER = "<!-- needs-human-queue -->"
TITLE = "Needs your eyes"
WAIT_LABELS = ("merge-risk:high", "no-auto-merge", "needs-human")
LINES_PER_HOUR = 450
MIN_MINUTES = 5
MAX_BULLETS = 8
MAX_BULLET_CHARS = 240

# Not read by a human: lockfiles, project files, generated and binary files.
IGNORED = (
    "*.lock", "*/Podfile.lock", "Podfile.lock", "*Package.resolved", "*package-lock.json",
    "*.pbxproj", "ios/Pods/*", "*/Pods/*", "*.xcassets/*", "*.png", "*.jpg", "*.jpeg",
    "*.gif", "*.pdf", "*.mp4", "*.mov", "*.json.gz", "*.min.js", "*generated*", "*.generated.*",
    "screenshots/*",
)

# (label, regex on the path) for the "risky paths touched" list.
RISKY = (
    ("workers/", re.compile(r"^workers/")),
    ("iOS push", re.compile(r"^ios/.*(Push|Notification|FCM|OneSignal|Alert)", re.I)),
    ("purchases", re.compile(r"(Purchase|StoreKit|Subscription|Paywall|IAP)", re.I)),
    (".github/", re.compile(r"^\.github/")),
)

SECRETISH = re.compile(
    r"\b(?:ghp|gho|ghs|github_pat|sk|pk|xox[bp]|AIza|AKIA)[-_A-Za-z0-9]{12,}|"
    r"\b[A-Za-z0-9+_-]{32,}\b|(?:token|secret|password|api[_ -]?key)\s*[:=]\s*\S+",
    re.I,
)
LGTM_RE = re.compile(r"^\W*(?!(?:not|never|almost|no)\b)(?:[\w.-]+\s+){0,3}LGTM\b", re.I)
CHANGES_RE = re.compile(r"^\W*(?:[\w.-]+\s+){0,3}\W*(?:changes needed|changes requested)\b", re.I)
TRUSTED = ("OWNER", "MEMBER", "COLLABORATOR")  # a stranger's comment never counts
HUMAN_RE = re.compile(r"^\W*human check\W*:?\s*(.*)$", re.I)
BULLET_RE = re.compile(r"^\s*[-*•]\s+(.*\S)\s*$")


def is_ignored(path: str) -> bool:
    return any(fnmatch.fnmatch(path, p) for p in IGNORED)


def read_minutes(files: list[dict]) -> tuple[int, int]:
    """(minutes, counted lines): lines / 450 per hour, rounded up, at least 5 minutes."""
    lines = sum(f.get("additions", 0) + f.get("deletions", 0) for f in files if not is_ignored(f["filename"]))
    minutes = math.ceil(lines / LINES_PER_HOUR * 60)
    return max(MIN_MINUTES, minutes), lines


def format_minutes(m: int) -> str:
    h, r = divmod(m, 60)
    if not h:
        return f"{m} min"
    return f"{h} h {r} min" if r else f"{h} h"


def risky_paths(files: list[dict]) -> list[str]:
    out = []
    for label, rx in RISKY:
        hits = sorted({f["filename"] for f in files if rx.search(f["filename"])})
        if hits:
            shown = ", ".join(f"`{h}`" for h in hits[:3])
            more = f" (+{len(hits) - 3} more)" if len(hits) > 3 else ""
            out.append(f"**{label}** {shown}{more}")
    return out


def safe_bullet(text: str) -> str | None:
    """A reviewer's bullet, or None when it must not be copied into a public comment."""
    text = re.sub(r"<!--.*?-->|<[^>]+>", "", text).strip()
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)  # keep link text, drop the URL
    if not text or check_text(text, "bullet") or SECRETISH.search(text) or re.search(r"https?://", text):
        return None
    text = text.replace("@", "@​")  # no pings
    return text if len(text) <= MAX_BULLET_CHARS else text[: MAX_BULLET_CHARS - 1].rstrip() + "…"


def human_checks(items: list[dict]) -> tuple[list[str], int]:
    """`Human check:` bullets of the latest LGTM review/comment, unless changes were asked later.

    items: [{"user", "created", "body", "assoc"}]. Only OWNER/MEMBER/COLLABORATOR count, never
    claude[bot]. Returns (bullets, number withheld by the filter).
    """
    last = None
    for it in sorted(items, key=lambda i: i["created"]):
        if it["user"] == "claude[bot]" or it.get("assoc") not in TRUSTED:
            continue
        first = (it["body"] or "").lstrip().split("\n", 1)[0]
        if CHANGES_RE.match(first):
            last = None
        elif LGTM_RE.match(first):
            last = it
    if not last:
        return [], 0
    bullets: list[str] = []
    in_block = False
    for line in last["body"].splitlines():
        m = HUMAN_RE.match(line)
        if m:
            in_block = True
            if m.group(1).strip():  # "Human check: do X"
                bullets.append(m.group(1))
            continue
        if in_block:
            b = BULLET_RE.match(line)
            if b:
                bullets.append(b.group(1))
            elif line.strip():
                in_block = False
    out = [b for b in map(safe_bullet, bullets) if b]
    return out[:MAX_BULLETS], len(bullets) - len(out)


def waiting_labels(pr: dict) -> list[str]:
    names = {l["name"] for l in pr.get("labels", [])}
    return [l for l in WAIT_LABELS if l in names]


def needs_eyes(pr: dict) -> bool:
    return pr.get("state") == "open" and not pr.get("draft") and bool(waiting_labels(pr))


def build_comment(pr: dict, files: list[dict], bullets: list[str], withheld: int = 0) -> str:
    minutes, lines = read_minutes(files)
    why = ", ".join(f"`{l}`" for l in waiting_labels(pr))
    parts = [
        MARKER,
        f"## {TITLE}",
        "",
        f"**Why:** {why}",
        f"**Read time:** ~{format_minutes(minutes)} ({lines} changed lines, lockfiles and generated files left out; {LINES_PER_HOUR} lines/hour, minimum {MIN_MINUTES} min)",
    ]
    risky = risky_paths(files)
    parts.append("**Risky paths:** " + ("; ".join(risky) if risky else "none of workers/, iOS push, purchases, .github/"))
    parts += ["", "**Human check:**"]
    parts += [f"- {b}" for b in bullets] if bullets else ["- none from the reviewer"]
    if withheld:
        parts.append(f"- {withheld} bullet(s) withheld by the public-text filter; see the reviewer's LGTM")
    parts += ["", f"<sub>Head `{pr['head']['sha'][:7]}`. Updated by `tools/needs_human.py`; removed when the labels are gone.</sub>"]
    return "\n".join(parts) + "\n"


def queue_line(pr: dict, files: list[dict]) -> str:
    minutes, _ = read_minutes(files)
    why = ", ".join(waiting_labels(pr))
    return f"- [#{pr['number']} {pr['title']}]({pr['html_url']}) — {why} — ~{format_minutes(minutes)}"


# ---- GitHub I/O (gh CLI, built-in token) ----

def gh(*args: str, body: dict | None = None):
    cmd = ["gh", *args]
    if body is not None:
        cmd += ["--input", "-"]
    r = subprocess.run(cmd, input=json.dumps(body) if body is not None else None,
                       capture_output=True, text=True, check=True)
    return json.loads(r.stdout) if r.stdout.strip() else None


def paged(path: str) -> list:
    data = gh("api", "--paginate", "--slurp", path)
    return [x for page in data for x in (page if isinstance(page, list) else [page])]


def review_items(repo: str, n: int) -> list[dict]:
    items = [{"user": r["user"]["login"], "created": r.get("submitted_at") or "", "body": r.get("body") or "",
              "assoc": r.get("author_association")}
             for r in paged(f"repos/{repo}/pulls/{n}/reviews") if r.get("state") != "DISMISSED"]
    items += [{"user": c["user"]["login"], "created": c["created_at"], "body": c.get("body") or "",
               "assoc": c.get("author_association")}
              for c in paged(f"repos/{repo}/issues/{n}/comments")]
    return items


def sticky(repo: str, n: int) -> dict | None:
    for c in paged(f"repos/{repo}/issues/{n}/comments"):
        if MARKER in (c.get("body") or "") and c["user"]["login"] == "github-actions[bot]":
            return c
    return None


def sync_pr(repo: str, n: int, dry: bool) -> str:
    pr = gh("api", f"repos/{repo}/pulls/{n}")
    existing = sticky(repo, n)
    if not needs_eyes(pr):
        if existing:
            if not dry:
                gh("api", "-X", "DELETE", f"repos/{repo}/issues/comments/{existing['id']}")
            return "removed"
        return "none"
    files = paged(f"repos/{repo}/pulls/{n}/files")
    bullets, withheld = human_checks(review_items(repo, n))
    body = build_comment(pr, files, bullets, withheld)
    if dry:
        print(body)
        return "dry-run"
    if existing:
        if existing["body"] == body:
            return "unchanged"
        gh("api", "-X", "PATCH", f"repos/{repo}/issues/comments/{existing['id']}", body={"body": body})
        return "updated"
    gh("api", "-X", "POST", f"repos/{repo}/issues/{n}/comments", body={"body": body})
    return "created"


def sync_queue(repo: str, dry: bool) -> str:
    prs = [p for p in paged(f"repos/{repo}/pulls?state=open&per_page=100") if needs_eyes(p)]
    lines = [queue_line(p, paged(f"repos/{repo}/pulls/{p['number']}/files")) for p in prs]
    body = "\n".join([QUEUE_MARKER, "Open PRs waiting for you (updated every 6 h by `needs-human.yml`):", "", *lines]) + "\n"
    issues = paged(f"repos/{repo}/issues?state=open&per_page=100")
    issue = next((i for i in issues if "pull_request" not in i and QUEUE_MARKER in (i.get("body") or "")
                  and i["user"]["login"] == "github-actions[bot]"), None)
    if dry:
        print(body)
        return "dry-run"
    if not lines:
        if issue:
            gh("api", "-X", "PATCH", f"repos/{repo}/issues/{issue['number']}", body={"state": "closed", "state_reason": "completed"})
            return "closed"
        return "none"
    if issue:
        if issue["body"] != body:
            gh("api", "-X", "PATCH", f"repos/{repo}/issues/{issue['number']}", body={"body": body})
        return "updated"
    gh("api", "-X", "POST", f"repos/{repo}/issues", body={"title": TITLE, "body": body})
    return "created"


def main(argv: list[str]) -> int:
    repo = os.environ["REPO"]
    dry = "--dry-run" in argv
    if argv and argv[0] == "pr":
        print(sync_pr(repo, int(os.environ["PR"]), dry))
    elif argv and argv[0] == "queue":
        print(sync_queue(repo, dry))
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
