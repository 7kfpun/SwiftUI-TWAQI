#!/usr/bin/env python3
"""Fail when a pull request's diff would ship real secrets or secret files.

    python3 tools/check_secret_files.py <base-sha> <head-sha>

Looks at the net change the PR would merge (`git diff base...head`), so it needs
both commits locally (CI checks out with fetch-depth 0). It fails on:

1. Secret files added or changed: debug.xcconfig, release.xcconfig,
   GoogleService-Info.plist, .env / .env.*, .dev.vars (Wrangler), signing keys
   and profiles (*.p8, *.p12, *.mobileprovision, ...). Examples such as
   example.xcconfig or .env.example are fine.
2. Any new file that .gitignore (at base or head) excludes — it was force-added.
3. Added lines carrying a real-looking secret: a secret-named setting with a
   value in an .xcconfig / .env file (DirectusFeedbackToken = abc...), or a
   high-confidence key format (Google API key, private key block, GitHub /
   Slack / AWS / OneSignal tokens, Sentry DSN) in any text file.
   Placeholders ("placeholder", "example", "your-...", "<...>", $(VAR)) pass.

Values are never printed, only file, line and rule. Standard library only.
TruffleHog (Vulnerability checks) separately fails on *verified* live secrets
anywhere in the PR's commits; this catches the unverifiable ones.
"""

import fnmatch
import os
import pathlib
import re
import subprocess
import sys
import tempfile

SECRET_FILE_NAMES = {
    "debug.xcconfig",
    "release.xcconfig",
    "googleservice-info.plist",
    ".env",
    ".dev.vars",
}
SECRET_FILE_GLOBS = (
    ".env.*",
    ".dev.vars.*",
    "*.p8",
    "*.p12",
    "*.pfx",
    "*.mobileprovision",
    "*.provisionprofile",
    "*.keystore",
    "*.jks",
    "authkey_*",
    "*service-account*.json",
    "*serviceaccount*.json",
)
# Template copies of the files above are meant to be committed.
EXAMPLE_MARKERS = ("example", "sample", "template", "placeholder")

ENV_LIKE_GLOBS = ("*.xcconfig", ".env*", ".dev.vars*", "*.env")
SECRET_SETTING = re.compile(
    r"(?i)(token|secret|password|passwd|api_?key|private_?key|dsn|credential|auth_?key)"
)
SETTING_LINE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_.\[\]=*-]*)\s*[=:]\s*(.*)$")

PATTERNS = (
    ("Google API key", re.compile(r"AIza[0-9A-Za-z_\-]{35}")),
    ("private key block", re.compile(r"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----")),
    ("GitHub token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})")),
    ("Slack token", re.compile(r"\bxox[abposr]-[A-Za-z0-9-]{10,}")),
    ("AWS access key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("OneSignal API key", re.compile(r"\bos_v2_(?:app|org)_[a-z0-9]{40,}")),
    ("Sentry DSN", re.compile(r"https://[0-9a-f]{32}@[a-z0-9.-]*sentry\.io/\d+")),
)
PLACEHOLDER = re.compile(
    r"(?i)(placeholder|example|dummy|changeme|change-me|your[-_ ]|xxxx|redacted|<[^>]*>|\$\(|\$\{|\*\*\*)"
)


def git(*args, check=True):
    return subprocess.run(["git", *args], check=check, capture_output=True, text=True).stdout


def is_example(name):
    lowered = name.lower()
    return any(marker in lowered for marker in EXAMPLE_MARKERS)


def secret_file_rule(path):
    original = pathlib.PurePosixPath(path).name
    name = original.lower()
    if is_example(name):
        return None
    if name in SECRET_FILE_NAMES:
        return f"secret file {original} must stay untracked (copy it from an example instead)"
    for pattern in SECRET_FILE_GLOBS:
        if fnmatch.fnmatch(name, pattern):
            return f"secret file matching {pattern} must not be committed"
    return None


def ignored(paths, base):
    """Paths that the head or the base .gitignore rules exclude."""
    if not paths:
        return set()
    hits = set()
    payload = "\n".join(paths) + "\n"
    head = subprocess.run(
        ["git", "check-ignore", "--no-index", "--stdin"], input=payload, capture_output=True, text=True
    )
    hits.update(line for line in head.stdout.splitlines() if line)
    # Base rules too, so a PR can't drop a .gitignore line and add the file in one go.
    base_rules = git("show", f"{base}:.gitignore", check=False)
    if base_rules:
        with tempfile.NamedTemporaryFile("w", suffix=".gitignore", delete=False) as handle:
            handle.write(base_rules)
            rules_path = handle.name
        try:
            result = subprocess.run(
                ["git", "-c", f"core.excludesFile={rules_path}", "check-ignore", "--no-index", "--stdin"],
                input=payload,
                capture_output=True,
                text=True,
            )
            hits.update(line for line in result.stdout.splitlines() if line)
        finally:
            os.unlink(rules_path)
    return hits


def changed_files(base, head):
    """(status, path) for every file the PR adds, changes, copies or renames to."""
    out = git("diff", "--name-status", "-M", "-z", f"{base}...{head}")
    fields = out.split("\0")
    entries, i = [], 0
    while i < len(fields) and fields[i]:
        status = fields[i]
        if status[0] in "RC":
            entries.append((status[0], fields[i + 2]))
            i += 3
        else:
            entries.append((status[0], fields[i + 1]))
            i += 2
    return [(status, path) for status, path in entries if status != "D"]


def added_lines(base, head):
    """Yield (path, line number, text) for every line the PR adds."""
    out = git("diff", "-U0", "--no-color", "--no-ext-diff", "-M", f"{base}...{head}")
    path, line_no = None, 0
    for raw in out.splitlines():
        if raw.startswith("+++ "):
            target = raw[4:]
            path = None if target == "/dev/null" else target[2:] if target.startswith("b/") else target
            continue
        if raw.startswith("@@"):
            match = re.search(r"\+(\d+)", raw)
            line_no = int(match.group(1)) if match else 0
            continue
        if path is None or raw.startswith("---"):
            continue
        if raw.startswith("+"):
            yield path, line_no, raw[1:]
            line_no += 1


def setting_value(path, text):
    """The value of a secret-named KEY = value line in an env-like file, else None."""
    name = pathlib.PurePosixPath(path).name.lower()
    if not any(fnmatch.fnmatch(name, pattern) for pattern in ENV_LIKE_GLOBS):
        return None
    match = SETTING_LINE.match(text)
    if not match or not SECRET_SETTING.search(match.group(1)):
        return None
    value = match.group(2)
    if name.endswith(".xcconfig"):
        value = value.split("//", 1)[0]  # xcconfig comment; URLs are written https:\/\/
    else:
        value = re.split(r"\s+#", value, 1)[0]
    return value.strip().strip("'\"")


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    base, head = argv[1], argv[2]
    findings = []

    files = changed_files(base, head)
    for status, path in files:
        rule = secret_file_rule(path)
        if rule:
            findings.append((path, None, rule))
    new_files = [path for status, path in files if status in "ARC"]
    for path in sorted(ignored(new_files, base)):
        findings.append((path, None, "file is excluded by .gitignore but was force-added"))

    for path, line_no, text in added_lines(base, head):
        value = setting_value(path, text)
        if value and not PLACEHOLDER.search(value):
            findings.append((path, line_no, "secret-named setting has a real-looking value"))
            continue
        for label, pattern in PATTERNS:
            for match in pattern.finditer(text):
                if PLACEHOLDER.search(match.group(0)):
                    continue
                findings.append((path, line_no, label))
                break

    annotate = bool(os.environ.get("GITHUB_ACTIONS"))
    if not findings:
        print(f"No secret files or secret values in {len(files)} changed file(s).")
        return 0
    seen = set()
    for path, line_no, rule in findings:
        if (path, line_no, rule) in seen:
            continue
        seen.add((path, line_no, rule))
        where = f"{path}:{line_no}" if line_no else path
        if annotate:
            location = f"file={path},line={line_no}" if line_no else f"file={path}"
            print(f"::error {location}::{rule}")
        else:
            print(f"error: {where}: {rule}")
    print(
        f"\n{len(seen)} finding(s). Remove the file or value from the branch (rewrite the commits: "
        "the repository is public, so anything pushed is already exposed) and rotate any real key."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
