#!/usr/bin/env python3
"""How much of the `Unit tests` job a pull request needs (FOX-79).

Three levels, decided from the PR's changed files. The highest level wins:

  skip   only workers/, services/, web/, fastlane/, assets/, docs (.md), media, or .github/
         other than the CI workflow and its build action changed: nothing runs and the
         check is green.
  build  any other path (Swift, strings, asset catalogs, widget / watch / visionOS,
         project.pbxproj): build-for-testing only, no simulator.
  test   a guarded path changed (the sources and test files behind the CI subset,
         listed in ci.yml as CI_GUARDED_PATHS), or the CI workflow, its build action
         (.github/actions/unit-tests-build, FOX-65), this script, the Podfile /
         Podfile.lock or Package.resolved: build, boot, run the subset.

The PR label `ci-full-tests`, an empty file list, or a failed API call give `test`:
the job never skips on doubt.

Both lists (CI_TEST_SUITES and CI_GUARDED_PATHS) live in the job's `env` in
.github/workflows/ci.yml, and this script reads them from there.

Usage:
  ci_test_level.py decide --files FILE [--labels FILE] [--api-error]
  ci_test_level.py check            # the lists in ci.yml are in step with the repo,
                                    # and ci-cache.yml's config step matches ci.yml's
Tests: python3 -m unittest discover -s tools -p 'test_ci_test_level.py'
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath

SKIP, BUILD, TEST = "skip", "build", "test"
RANK = {SKIP: 0, BUILD: 1, TEST: 2}

FORCE_LABEL = "ci-full-tests"
WORKFLOW = ".github/workflows/ci.yml"
# The job's cache and build steps, shared with ci-cache.yml (FOX-65).
BUILD_ACTION = ".github/actions/unit-tests-build/**"
# Fills the caches from master. It carries a copy of ci.yml's config step,
# which `check` keeps identical.
CACHE_WORKFLOW = ".github/workflows/ci-cache.yml"
CONFIG_STEP = "Prepare gitignored config"

# Changing how the job runs, or what it builds against, runs the whole job.
ALWAYS_TEST = (
    WORKFLOW,
    BUILD_ACTION,
    "tools/ci_test_level.py",
    "tools/test_ci_test_level.py",
    "Podfile",
    "Podfile.lock",
    "**/Package.resolved",
)

# These do not feed the app build. workers/ is checked by the Workers workflow,
# services/ is Cloud Run, deployed by hand (services/twaqi-api/README.md).
SKIP_PREFIXES = ("assets/", "fastlane/", "services/", "web/", "workers/", ".github/")
DOC_SUFFIXES = {".md", ".markdown"}
MEDIA_SUFFIXES = {
    ".m4a", ".mp3", ".wav", ".aac", ".caf", ".aiff", ".aif", ".m4b", ".flac", ".ogg",
    ".mp4", ".mov", ".m4v", ".avi", ".webm",
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic", ".svg", ".pdf",
}

# Directories never searched by `check`.
IGNORED_DIRS = {".git", "Pods", "DerivedData", "node_modules", "build", ".build"}


def normalize(path: str) -> str:
    path = path.strip().replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def glob_regex(pattern: str) -> re.Pattern[str]:
    """`*` and `?` stay inside one path segment; `**/` spans any directories."""
    pattern = normalize(pattern)
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    # Case-insensitive: the Mac file system is, so a case-only rename must still match.
    return re.compile("".join(out) + r"\Z", re.IGNORECASE)


def matches(path: str, patterns) -> bool:
    path = normalize(path)
    return any(glob_regex(pattern).match(path) for pattern in patterns)


def parse_list(text: str) -> list[str]:
    """One entry per line; blank lines and whole-line `#` comments are dropped."""
    items = []
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            items.append(line)
    return items


def classify(path: str, guarded) -> str:
    path = normalize(path)
    if matches(path, ALWAYS_TEST) or matches(path, guarded):
        return TEST
    lowered = path.lower()
    if lowered.startswith(SKIP_PREFIXES):
        return SKIP
    suffix = PurePosixPath(lowered).suffix
    if suffix in DOC_SUFFIXES or suffix in MEDIA_SUFFIXES:
        return SKIP
    return BUILD


@dataclass
class Decision:
    level: str
    reason: str
    files: list[str] = field(default_factory=list)  # the files that decided it


def decide(files, labels=(), guarded=(), api_error=False) -> Decision:
    files = [normalize(path) for path in files if path.strip()]
    labels = {label.strip() for label in labels if label.strip()}
    if api_error:
        return Decision(TEST, "the pull request's files or labels could not be read")
    if FORCE_LABEL in labels:
        return Decision(TEST, f"the pull request has the {FORCE_LABEL} label")
    if not files:
        return Decision(TEST, "no changed files were listed")
    levels = {path: classify(path, guarded) for path in files}
    level = max(levels.values(), key=RANK.__getitem__)
    reason = {
        TEST: "guarded paths, the CI workflow or the dependency pins changed",
        BUILD: "app files changed, none of them guarded by the CI subset",
        SKIP: "only Workers, web, fastlane, assets, docs, media or .github files changed",
    }[level]
    return Decision(level, reason, [path for path in files if levels[path] == level])


def workflow_block(text: str, key: str) -> str:
    """The value of a `KEY: |` block scalar in a workflow file, without parsing YAML."""
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = re.match(rf"^(\s*){re.escape(key)}:\s*\|[-+]?\s*$", line)
        if not match:
            continue
        indent = len(match.group(1))
        body = []
        for following in lines[index + 1:]:
            if following.strip() and len(following) - len(following.lstrip()) <= indent:
                break
            body.append(following)
        return "\n".join(body)
    raise ValueError(f"{key}: | not found in the workflow")


def step_run(text: str, name: str) -> str:
    """The `run: |` script of the step called `name`, dedented, without parsing YAML."""
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if not re.match(rf"^\s*-\s+name:\s*{re.escape(name)}\s*$", line):
            continue
        step_indent = len(line) - len(line.lstrip())
        for offset, following in enumerate(lines[index + 1:], start=index + 1):
            if following.strip() and len(following) - len(following.lstrip()) <= step_indent:
                break
            if re.match(r"^\s*run:\s*\|[-+]?\s*$", following):
                script = workflow_block("\n".join(lines[offset:]), "run").splitlines()
                cut = min((len(l) - len(l.lstrip()) for l in script if l.strip()), default=0)
                return "\n".join(l[cut:] for l in script).strip()
        raise ValueError(f"step {name!r} has no `run: |` script")
    raise ValueError(f"step {name!r} not found in the workflow")


def config_problems(workflow_text: str, cache_text: str) -> list[str]:
    """ci-cache.yml builds with the same placeholder config as ci.yml (FOX-65)."""
    try:
        if step_run(workflow_text, CONFIG_STEP) != step_run(cache_text, CONFIG_STEP):
            return [f"the {CONFIG_STEP!r} step in {CACHE_WORKFLOW} differs from {WORKFLOW}'s: copy it over"]
    except ValueError as error:
        return [str(error)]
    return []


def load_lists(workflow: Path) -> tuple[list[str], list[str]]:
    text = workflow.read_text()
    return (
        parse_list(workflow_block(text, "CI_TEST_SUITES")),
        parse_list(workflow_block(text, "CI_GUARDED_PATHS")),
    )


def repo_files(root: Path) -> list[str]:
    found = []
    for directory, subdirs, names in os.walk(root):
        subdirs[:] = [name for name in subdirs if name not in IGNORED_DIRS]
        for name in names:
            found.append(Path(directory, name).relative_to(root).as_posix())
    return found


def check(root: Path, suites, guarded) -> list[str]:
    """Problems that would let the two lists drift apart; empty when in step."""
    problems = []
    if not suites:
        problems.append("CI_TEST_SUITES is empty")
    if not guarded:
        problems.append("CI_GUARDED_PATHS is empty")
    files = repo_files(root)
    for pattern in guarded:
        if not any(matches(path, [pattern]) for path in files):
            problems.append(f"CI_GUARDED_PATHS entry matches no file: {pattern}")
    tests = sorted(path for path in files if path.startswith("TWAQITests/") and path.endswith(".swift"))
    for suite in suites:
        declared = re.compile(rf"\bclass\s+{re.escape(suite)}\b")
        homes = [path for path in tests if declared.search((root / path).read_text(errors="replace"))]
        if not homes:
            problems.append(f"CI_TEST_SUITES suite is not declared in TWAQITests/: {suite}")
        for home in homes:
            if classify(home, guarded) != TEST:
                problems.append(f"{suite} lives in {home}, which CI_GUARDED_PATHS does not list")
    return problems


def read_lines(path: str | None) -> list[str]:
    if not path:
        return []
    return Path(path).read_text().splitlines()


def main(argv=None) -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--workflow", type=Path, default=root / WORKFLOW)
    commands = parser.add_subparsers(dest="command", required=True)
    decide_cmd = commands.add_parser("decide", help="print the level for a list of changed files")
    decide_cmd.add_argument("--files", required=True, help="file with one changed path per line")
    decide_cmd.add_argument("--labels", help="file with one PR label per line")
    decide_cmd.add_argument("--api-error", action="store_true", help="the file or label list could not be read")
    commands.add_parser("check", help="the lists in the workflow are in step with the repository")
    args = parser.parse_args(argv)

    suites, guarded = load_lists(args.workflow)
    if args.command == "check":
        problems = check(root, suites, guarded)
        problems += config_problems(args.workflow.read_text(), (root / CACHE_WORKFLOW).read_text())
        for problem in problems:
            print(f"::error::{problem}")
        if not problems:
            print(f"{len(suites)} suites, {len(guarded)} guarded paths: in step. {CACHE_WORKFLOW} config matches.")
        return 1 if problems else 0

    files = [] if args.api_error else read_lines(args.files)
    decision = decide(files, read_lines(args.labels), guarded, api_error=args.api_error)
    print(f"Test level: {decision.level} ({decision.reason})")
    if decision.files:
        print("Files that decided it:")
        print("\n".join(f"  {path}" for path in decision.files))
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as handle:
            handle.write(f"level={decision.level}\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as handle:
            handle.write(f"**Unit tests level: `{decision.level}`**: {decision.reason}.\n\n")
            for path in decision.files[:50]:
                handle.write(f"- `{path}`\n")
            if len(decision.files) > 50:
                handle.write(f"- … {len(decision.files) - 50} more\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
