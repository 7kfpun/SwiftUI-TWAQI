#!/usr/bin/env python3
"""The repo is public: keep infra details out of what a pull request adds.

Checks the PR title and description, the PR's commit messages, and every line the PR
adds, for:

  host     a hostname that isn't a public website (taiwanair.wahthefox.com,
           kf-twaqi.web.app, kf-nihongo.web.app, ...): our API / webcam host, Directus,
           workers.dev, Cloud Run, API Gateway, appspot, firebaseio.
  ip       an IPv4 address or CIDR range (127.0.0.1 and 0.0.0.0 are fine).
  email    an email address other than the public support address and bot/no-reply ones.
  posture  wording about network exposure: authorized networks, 0.0.0.0/0, "open to the
           internet", brute force, ...

Hosts may still appear in files that need them to work (FILES_THAT_NEED_HOSTS): config,
scripts, app constants and tests. Everything else names a host by its role ("the webcam
host", "Directus"); see docs/ci-cd-guardrails.md#public-repo-what-stays-out.

Usage:
  public_text_check.py --base <sha> --head <sha>   # PR_TITLE / PR_BODY from the environment
  public_text_check.py --text FILE                 # check one text (for local use)
Tests: python3 -m unittest discover -s tools -p 'test_public_text_check.py'
"""

from __future__ import annotations

import argparse
import fnmatch
import os
import re
import subprocess
import sys
from dataclasses import dataclass

# Public websites: fine anywhere.
ALLOWED_HOSTS = {
    "taiwanair.wahthefox.com",
    "kf-twaqi.web.app",
    "kf-nihongo.web.app",
}

# Files whose code or config needs a real host to work. Hosts are fine on their added
# lines; IPs, emails and posture wording are still checked.
FILES_THAT_NEED_HOSTS = (
    "workers/*/wrangler.jsonc",
    "workers/*/src/*",
    "workers/*/test/*",
    "workers/*/directus/*",
    "services/*/scripts/*",
    "services/*/test/fixtures/*",
    "ios/TWAQI/Config/example.xcconfig",
    "ios/TWAQI/**/*.swift",
    "ios/TWAQITests/*.swift",
    "web/*.html",
    "web/**/*.html",
    ".github/workflows/*.yml",
)

# Lines from these files aren't checked at all (generated or vendored).
SKIPPED_FILES = (
    "*.lock", "**/package-lock.json", "ios/Pods/*", "**/*.pbxproj", "*.png", "*.jpg",
    # This checker and its tests spell out the patterns (with made-up values).
    "tools/public_text_check.py", "tools/test_public_text_check.py",
)

HOST = re.compile(
    r"\b(?:[a-z0-9-]+\.)*(?:"
    r"[a-z0-9-]+\.wahthefox\.com|"
    r"[a-z0-9-]+\.workers\.dev|"
    r"[a-z0-9-]+\.(?:[a-z0-9-]+\.)?run\.app|"
    r"[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com|"
    r"[a-z0-9-]+\.appspot\.com|"
    r"[a-z0-9-]+\.firebaseio\.com|"
    r"[a-z0-9-]+\.cloudfunctions\.net"
    r")\b",
    re.IGNORECASE,
)
IP = re.compile(r"(?<![\d.])(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}(?:/\d{1,2})?(?![\d.])")
FINE_IPS = {"127.0.0.1", "0.0.0.0"}
EMAIL = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
FINE_EMAIL = re.compile(
    r"^info@(wahthefox\.com|dllm\.io)$|@users\.noreply\.github\.com$|^noreply@|@anthropic\.com$|@example\.(com|org|net)$|^[^@]+@[^@]+\.(png|jpg|jpeg|pdf)$",
    re.IGNORECASE,
)
POSTURE = re.compile(
    r"0\.0\.0\.0/0|authori[sz]ed[ -]networks?|open to the internet|publicly (?:accessible|reachable|exposed)|"
    r"brute[ -]?forc|password[- ]guess|firewall rule",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Finding:
    where: str  # "PR title", "PR description", "commit abc1234", or a file path
    line: int  # 0 when not a file line
    kind: str
    text: str

    def annotation(self) -> str:
        loc = f"file={self.where},line={self.line}," if self.line else ""
        return f"::error {loc}title=Public text ({self.kind})::{self.where}: {self.text}"


def _matches(path: str, patterns: tuple[str, ...]) -> bool:
    return any(fnmatch.fnmatch(path, p) or fnmatch.fnmatch(path, p.replace("**/", "")) for p in patterns)


def check_text(text: str, where: str, line_offset: int = 0, hosts_allowed: bool = False) -> list[Finding]:
    """Findings in one text. line numbers count from line_offset + 1 when line_offset > 0."""
    found: list[Finding] = []
    for i, line in enumerate(text.splitlines(), start=1):
        n = line_offset + i if line_offset else 0
        if not hosts_allowed:
            for m in HOST.finditer(line):
                if m.group(0).lower() not in ALLOWED_HOSTS:
                    found.append(Finding(where, n, "host", m.group(0)))
        for m in IP.finditer(line):
            if m.group(0) not in FINE_IPS:
                found.append(Finding(where, n, "ip", m.group(0)))
        for m in EMAIL.finditer(line):
            if not FINE_EMAIL.search(m.group(0)):
                found.append(Finding(where, n, "email", m.group(0)))
        for m in POSTURE.finditer(line):
            found.append(Finding(where, n, "posture", m.group(0)))
    return found


def added_lines(base: str, head: str) -> dict[str, list[tuple[int, str]]]:
    """{path: [(line number in head, text)]} for lines the PR adds."""
    diff = subprocess.run(
        ["git", "diff", "--unified=0", "--no-color", "--no-ext-diff", f"{base}...{head}"],
        check=True, capture_output=True, text=True,
    ).stdout
    out: dict[str, list[tuple[int, str]]] = {}
    path = None
    n = 0
    for raw in diff.splitlines():
        if raw.startswith("+++ "):
            path = raw[6:] if raw.startswith("+++ b/") else None
            continue
        if raw.startswith("@@"):
            m = re.search(r"\+(\d+)", raw)
            n = int(m.group(1)) if m else 0
            continue
        if path and raw.startswith("+"):
            out.setdefault(path, []).append((n, raw[1:]))
            n += 1
    return out


def commit_messages(base: str, head: str) -> list[tuple[str, str]]:
    log = subprocess.run(
        ["git", "log", "--format=%h%x00%B%x01", f"{base}..{head}"],
        check=True, capture_output=True, text=True,
    ).stdout
    out = []
    for entry in log.split("\x01"):
        if "\x00" in entry:
            sha, msg = entry.strip("\n").split("\x00", 1)
            out.append((sha, msg))
    return out


def check_pr(base: str, head: str, title: str, body: str) -> list[Finding]:
    found = check_text(title, "PR title") + check_text(body, "PR description")
    for sha, msg in commit_messages(base, head):
        found += check_text(msg, f"commit {sha}")
    for path, lines in added_lines(base, head).items():
        if _matches(path, SKIPPED_FILES):
            continue
        needs_hosts = _matches(path, FILES_THAT_NEED_HOSTS)
        for n, text in lines:
            found += check_text(text, path, line_offset=n - 1 if n else 0, hosts_allowed=needs_hosts)
    # The same value on the same line once.
    return list(dict.fromkeys(found))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--base")
    ap.add_argument("--head")
    ap.add_argument("--text", help="check this file's text instead of a PR")
    args = ap.parse_args(argv)
    if args.text:
        with open(args.text, encoding="utf-8") as f:
            found = check_text(f.read(), args.text, line_offset=0)
    elif args.base and args.head:
        found = check_pr(args.base, args.head, os.environ.get("PR_TITLE", ""), os.environ.get("PR_BODY", ""))
    else:
        ap.error("pass --base and --head, or --text")
    for f in found:
        print(f.annotation())
    if found:
        print(
            f"{len(found)} finding(s). The repo is public: name hosts by role and leave IPs, "
            "network ranges, private emails and exposure details out "
            "(docs/ci-cd-guardrails.md#public-repo-what-stays-out). Linear is the place for them.",
            file=sys.stderr,
        )
        return 1
    print("Public text: nothing to flag.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
