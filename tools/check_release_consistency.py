#!/usr/bin/env python3
"""Check that the version, build numbers and What's New agree before a release.

Fails (exit 1) when:
  - ios/fastlane/Fastfile APP_VERSION differs from MARKETING_VERSION in any
    non-visionOS build configuration that sets one (app, widget, watch app,
    watch widget, notification extension);
  - those configurations do not all share one CURRENT_PROJECT_VERSION
    (App Store Connect rejects an app whose extensions carry a different build);
  - ios/fastlane/metadata/<locale>/release_notes.txt is missing, empty, or longer
    than App Store Connect's 4000-character limit, for en-US or zh-Hant.

visionOS (SDKROOT = xros) is reported but not checked: it ships its own build
numbers and can trail the iPhone version.

Used by CI (PR policy) and by `fastlane release_build` before it archives.
Standard library only. Run from anywhere:

    python3 tools/check_release_consistency.py [ios-root]

The root is the iOS app's directory, the one holding TWAQI.xcodeproj and
fastlane/ (ios/ since FOX-89). It defaults to ios/ in the checkout the script
sits in. CI runs master's copy of the script against the PR's checkout by
passing the PR's ios/.
"""

import os
import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).parent.parent / "ios").resolve()
PBXPROJ = ROOT / "TWAQI.xcodeproj" / "project.pbxproj"
FASTFILE = ROOT / "fastlane" / "Fastfile"
METADATA = ROOT / "fastlane" / "metadata"
LOCALES = ("en-US", "zh-Hant")
RELEASE_NOTES_LIMIT = 4000


def setting(settings, key):
    match = re.search(rf"^\s*{key} = (.+?);\s*$", settings, re.M)
    if not match:
        return None
    return match.group(1).strip().strip('"')


def build_configurations(text):
    """Yield (target, config name, buildSettings text) for every target config."""
    configs = {}
    for match in re.finditer(r"^\t\t([0-9A-F]{24}) /\* [^*]*? \*/ = \{\n(.*?)^\t\t\};", text, re.M | re.S):
        body = match.group(2)
        if "isa = XCBuildConfiguration;" not in body:
            continue
        name = re.search(r"^\t\t\tname = (.+?);", body, re.M)
        settings = re.search(r"buildSettings = \{\n(.*?)^\t\t\t\};", body, re.M | re.S)
        configs[match.group(1)] = (
            name.group(1).strip('"') if name else "?",
            settings.group(1) if settings else "",
        )

    pattern = (
        r'/\* Build configuration list for PBXNativeTarget "([^"]+)" \*/ = \{\n'
        r"\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = \((.*?)\);"
    )
    for match in re.finditer(pattern, text, re.S):
        target = match.group(1)
        for config_id in re.findall(r"[0-9A-F]{24}", match.group(2)):
            if config_id in configs:
                name, settings = configs[config_id]
                yield target, name, settings


def main():
    errors = []
    fastfile = FASTFILE.read_text()
    version_match = re.search(r'^APP_VERSION = "([^"]+)"', fastfile, re.M)
    if not version_match:
        errors.append("fastlane/Fastfile has no APP_VERSION = \"x.y.z\" line.")
        app_version = None
    else:
        app_version = version_match.group(1)

    rows = []
    for target, name, settings in build_configurations(PBXPROJ.read_text()):
        marketing = setting(settings, "MARKETING_VERSION")
        if marketing is None:
            continue  # test bundles and the like
        rows.append((target, name, marketing, setting(settings, "CURRENT_PROJECT_VERSION"), setting(settings, "SDKROOT")))

    if not rows:
        errors.append("No build configuration in project.pbxproj sets MARKETING_VERSION; the parser is out of date.")

    shipped = [row for row in rows if row[4] != "xros"]
    vision = [row for row in rows if row[4] == "xros"]

    for target, name, marketing, _, _ in shipped:
        if app_version and marketing != app_version:
            errors.append(f"{target} ({name}) MARKETING_VERSION = {marketing}, Fastfile APP_VERSION = {app_version}.")

    builds = sorted({row[3] for row in shipped}, key=str)
    if len(builds) > 1:
        detail = ", ".join(f"{t} ({n}) = {b}" for t, n, _, b, _ in shipped)
        errors.append(f"CURRENT_PROJECT_VERSION differs between shipped targets: {detail}.")
    elif builds and (builds[0] is None or not str(builds[0]).isdigit()):
        errors.append(f"CURRENT_PROJECT_VERSION is not a plain number: {builds[0]}.")

    for locale in LOCALES:
        path = METADATA / locale / "release_notes.txt"
        if not path.exists():
            errors.append(f"{path.relative_to(ROOT)} is missing.")
            continue
        notes = path.read_text(encoding="utf-8").strip()
        if not notes:
            errors.append(f"{path.relative_to(ROOT)} is empty.")
        elif len(notes) > RELEASE_NOTES_LIMIT:
            errors.append(f"{path.relative_to(ROOT)} is {len(notes)} characters; the limit is {RELEASE_NOTES_LIMIT}.")

    build = builds[0] if len(builds) == 1 else "?"
    print(f"iOS / watchOS: {app_version} ({build}) across {len({r[0] for r in shipped})} targets")
    for target, name, marketing, current, _ in vision:
        print(f"visionOS (not checked): {target} ({name}) {marketing} ({current})")

    if errors:
        for message in errors:
            print(f"::error::{message}" if os.environ.get("GITHUB_ACTIONS") else f"error: {message}")
        return 1
    print("Release version, build numbers and What's New are consistent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
