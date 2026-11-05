"""Tests for tools/ci_test_level.py (FOX-79).

python3 -m unittest discover -s tools -p 'test_ci_test_level.py'
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ci_test_level as level  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
GUARDED = [
    "ios/TWAQI/Utils/PushService.swift",
    "ios/TWAQI/**/StationCam*.swift",
    "ios/TWAQITests/PushServiceTests.swift",
]


def decide(*files, labels=(), api_error=False):
    return level.decide(list(files), labels, GUARDED, api_error=api_error)


class DecideTests(unittest.TestCase):
    def test_skip_only_lists(self):
        result = decide(
            "workers/twaqi-push-sender/src/index.ts",
            "web/index.html",
            "ios/fastlane/Fastfile",
            "assets/appstore/1.png",
            "README.md",
            "docs/ci-cd-guardrails.md",
            "screenshots/iphone/01.png",
            "ios/TWAQI/Resources/intro.mp4",
            ".github/pull_request_template.md",
        )
        self.assertEqual(result.level, level.SKIP)
        self.assertEqual(len(result.files), 9)

    def test_android_only_skips(self):
        # FOX-89: android/ never feeds the iOS build; its own CI comes with FOX-52.
        result = decide(
            "android/README.md",
            "android/app/build.gradle.kts",
            "android/app/src/main/java/com/kfpun/twaqi/MainActivity.kt",
            "android/app/src/main/res/values/strings.xml",
        )
        self.assertEqual(result.level, level.SKIP)
        self.assertEqual(len(result.files), 4)
        # An iOS file alongside still builds.
        mixed = decide("android/app/build.gradle.kts", "ios/TWAQI/ContentView.swift")
        self.assertEqual(mixed.level, level.BUILD)
        self.assertEqual(mixed.files, ["ios/TWAQI/ContentView.swift"])

    def test_a_workflow_other_than_ci_yml_skips(self):
        # PR #54 ran the whole job for this file alone.
        self.assertEqual(decide(".github/workflows/push-sender.yml").level, level.SKIP)
        self.assertEqual(decide(".github/workflows/workers.yml", "workers/x/a.ts").level, level.SKIP)

    def test_cloud_run_services_skip(self):
        # FOX-82: services/twaqi-api (Cloud Run) never feeds the app build.
        result = decide("services/twaqi-api/src/api.ts", "services/twaqi-api/Dockerfile")
        self.assertEqual(result.level, level.SKIP)

    def test_ci_yml_itself_tests(self):
        result = decide(".github/workflows/ci.yml", "docs/ci-cd-guardrails.md")
        self.assertEqual(result.level, level.TEST)
        self.assertEqual(result.files, [".github/workflows/ci.yml"])

    def test_the_shared_build_action_tests(self):
        # FOX-65: the job's config, caches and build live in this action.
        result = decide(".github/actions/unit-tests-build/action.yml", "README.md")
        self.assertEqual(result.level, level.TEST)
        self.assertEqual(result.files, [".github/actions/unit-tests-build/action.yml"])

    def test_the_master_cache_workflow_alone_skips(self):
        # ci-cache.yml runs on master only; the PR job does not use it.
        self.assertEqual(decide(".github/workflows/ci-cache.yml").level, level.SKIP)
        self.assertEqual(decide(".github/actions/other/action.yml").level, level.SKIP)

    def test_dependency_pins_and_this_script_test(self):
        for path in (
            "ios/Podfile",
            "ios/Podfile.lock",
            "ios/TWAQI.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            "tools/ci_test_level.py",
            "tools/test_ci_test_level.py",
        ):
            with self.subTest(path=path):
                self.assertEqual(decide(path).level, level.TEST)

    def test_a_view_change_builds(self):
        result = decide("ios/TWAQI/Views/Forecast/ForecastView.swift", "README.md")
        self.assertEqual(result.level, level.BUILD)
        self.assertEqual(result.files, ["ios/TWAQI/Views/Forecast/ForecastView.swift"])

    def test_other_app_paths_build(self):
        for path in (
            "ios/TWAQI.xcodeproj/project.pbxproj",
            "ios/TWAQI/Localization/en.lproj/Localizable.strings",
            "ios/TWAQI/Assets.xcassets/AppIcon.appiconset/Contents.json",
            "ios/TWAQIWidget/TWAQIWidget.swift",
            "ios/TWAQIWatch/ContentView.swift",
            "ios/TWAQIVision/Favourites.swift",
            "ios/TWAQITests/StationParsingTests.swift",
            "tools/pr_policy.py",
        ):
            with self.subTest(path=path):
                self.assertEqual(decide(path).level, level.BUILD)

    def test_a_guarded_file_tests(self):
        for path in (
            "ios/TWAQI/Utils/PushService.swift",
            "ios/TWAQI/Utils/StationCamFrameCache.swift",
            "ios/TWAQI/Views/Details/StationCamView.swift",
            "ios/TWAQITests/PushServiceTests.swift",
        ):
            with self.subTest(path=path):
                self.assertEqual(decide(path).level, level.TEST)

    def test_mixed_list_highest_level_wins(self):
        result = decide(
            "workers/twaqi-workers/src/forecast.ts",
            "ios/TWAQI/ContentView.swift",
            "ios/TWAQI/Utils/PushService.swift",
            "README.md",
        )
        self.assertEqual(result.level, level.TEST)
        self.assertEqual(result.files, ["ios/TWAQI/Utils/PushService.swift"])
        result = decide("workers/twaqi-workers/src/forecast.ts", "ios/TWAQI/ContentView.swift")
        self.assertEqual(result.level, level.BUILD)
        self.assertEqual(result.files, ["ios/TWAQI/ContentView.swift"])

    def test_empty_list_tests(self):
        self.assertEqual(decide().level, level.TEST)
        self.assertEqual(decide("", "  ").level, level.TEST)

    def test_api_error_tests(self):
        self.assertEqual(decide("README.md", api_error=True).level, level.TEST)

    def test_the_label_forces_test(self):
        self.assertEqual(decide("README.md", labels=["ci-full-tests"]).level, level.TEST)
        self.assertEqual(decide("README.md", labels=["documentation"]).level, level.SKIP)

    def test_paths_are_normalized_and_case_insensitive(self):
        self.assertEqual(decide("./ios/TWAQI/Utils/pushservice.swift").level, level.TEST)
        self.assertEqual(decide("Docs/NOTES.MD").level, level.SKIP)


class GlobTests(unittest.TestCase):
    def test_star_stays_in_one_segment(self):
        self.assertTrue(level.matches("ios/TWAQI/Utils/StationCamStore.swift", ["ios/TWAQI/Utils/StationCam*.swift"]))
        self.assertFalse(level.matches("ios/TWAQI/Utils/Sub/StationCam.swift", ["ios/TWAQI/Utils/StationCam*.swift"]))

    def test_double_star_spans_directories(self):
        self.assertTrue(level.matches("Package.resolved", ["**/Package.resolved"]))
        self.assertTrue(level.matches("a/b/Package.resolved", ["**/Package.resolved"]))
        self.assertFalse(level.matches("a/b/Package.resolved.bak", ["**/Package.resolved"]))


class WorkflowListTests(unittest.TestCase):
    def test_block_scalar_reading(self):
        text = (
            "jobs:\n"
            "  tests:\n"
            "    env:\n"
            "      CI_TEST_SUITES: |\n"
            "        ASuiteTests\n"
            "\n"
            "        # a comment line\n"
            "        BSuiteTests\n"
            "      OTHER: x\n"
        )
        self.assertEqual(level.parse_list(level.workflow_block(text, "CI_TEST_SUITES")), ["ASuiteTests", "BSuiteTests"])
        with self.assertRaises(ValueError):
            level.workflow_block(text, "CI_GUARDED_PATHS")

    def test_check_finds_drift(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "ios/TWAQITests").mkdir(parents=True)
            (root / "ios/TWAQI").mkdir(parents=True)
            (root / "ios/TWAQI/A.swift").write_text("")
            (root / "ios/TWAQITests/ATests.swift").write_text("final class ATests: XCTestCase {}\n")
            (root / "ios/TWAQITests/BTests.swift").write_text("final class BTests: XCTestCase {}\n")
            in_step = level.check(root, ["ATests"], ["ios/TWAQI/A.swift", "ios/TWAQITests/ATests.swift"])
            self.assertEqual(in_step, [])
            problems = level.check(root, ["ATests", "BTests", "CTests"], ["ios/TWAQI/A.swift", "ios/TWAQI/Gone.swift", "ios/TWAQITests/ATests.swift"])
            self.assertEqual(len(problems), 3, problems)
            self.assertTrue(any("ios/TWAQI/Gone.swift" in problem for problem in problems))
            self.assertTrue(any("BTests lives in ios/TWAQITests/BTests.swift" in problem for problem in problems))
            self.assertTrue(any("CTests" in problem for problem in problems))


class ConfigStepTests(unittest.TestCase):
    """FOX-65: ci-cache.yml carries a copy of ci.yml's config step."""

    PR = (
        "jobs:\n"
        "  tests:\n"
        "    steps:\n"
        "      - name: Other\n"
        "        run: |\n"
        "          echo other\n"
        "      - name: Prepare gitignored config\n"
        "        if: steps.scope.outputs.level != 'skip'\n"
        "        run: |\n"
        "          set -euo pipefail\n"
        "          cat > a <<'EOF'\n"
        "            <key>X</key>\n"
        "          EOF\n"
        "\n"
        "      - name: Next\n"
        "        run: echo next\n"
    )

    def cache(self, body):
        return (
            "jobs:\n"
            "  fill:\n"
            "    steps:\n"
            "      - name: Checkout repository\n"
            "        uses: actions/checkout@v4\n"
            "      - name: Prepare gitignored config\n"
            "        run: |\n"
            f"{body}"
            "      - name: Build\n"
            "        uses: ./x\n"
        )

    def test_same_script_at_another_indent_matches(self):
        body = "          set -euo pipefail\n          cat > a <<'EOF'\n            <key>X</key>\n          EOF\n"
        self.assertEqual(level.step_run(self.PR, level.CONFIG_STEP), "set -euo pipefail\ncat > a <<'EOF'\n  <key>X</key>\nEOF")
        self.assertEqual(level.config_problems(self.PR, self.cache(body)), [])
        self.assertEqual(level.config_problems(self.PR, self.cache(body.replace("          ", "            "))), [])

    def test_a_changed_placeholder_is_drift(self):
        body = "          set -euo pipefail\n          cat > a <<'EOF'\n            <key>Y</key>\n          EOF\n"
        problems = level.config_problems(self.PR, self.cache(body))
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("differs", problems[0])

    def test_a_missing_step_is_a_problem(self):
        problems = level.config_problems(self.PR, "jobs:\n  fill:\n    steps:\n      - name: Build\n        uses: ./x\n")
        self.assertEqual(len(problems), 1)
        self.assertIn("not found", problems[0])

    def test_the_real_workflows_match(self):
        self.assertEqual(
            level.config_problems((ROOT / level.WORKFLOW).read_text(), (ROOT / level.CACHE_WORKFLOW).read_text()),
            [],
        )


class RepositoryTests(unittest.TestCase):
    """The real lists in ci.yml against this checkout."""

    def test_ci_yml_lists_are_in_step(self):
        suites, guarded = level.load_lists(ROOT / level.WORKFLOW)
        self.assertEqual(level.check(ROOT, suites, guarded), [])

    def test_ci_yml_guards_each_area_from_the_ticket(self):
        _, guarded = level.load_lists(ROOT / level.WORKFLOW)
        for path in (
            "ios/TWAQI/Utils/PollutantCache.swift",
            "ios/TWAQI/Utils/OfflineCacheRetention.swift",
            "ios/TWAQI/Utils/PushService.swift",
            "ios/TWAQI/Utils/DirectusPushMirror.swift",  # OneSignalTags lives here
            "ios/TWAQI/Utils/FavouriteAlerts.swift",
            "ios/TWAQI/Utils/StationCamHistoryCache.swift",
            "ios/TWAQI/Utils/SettingsStore.swift",
        ):
            with self.subTest(path=path):
                self.assertEqual(level.classify(path, guarded), level.TEST)


if __name__ == "__main__":
    unittest.main()
