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
    "TWAQI/Utils/PushService.swift",
    "TWAQI/**/StationCam*.swift",
    "TWAQITests/PushServiceTests.swift",
]


def decide(*files, labels=(), api_error=False):
    return level.decide(list(files), labels, GUARDED, api_error=api_error)


class DecideTests(unittest.TestCase):
    def test_skip_only_lists(self):
        result = decide(
            "workers/twaqi-push-sender/src/index.ts",
            "web/index.html",
            "fastlane/Fastfile",
            "assets/appstore/1.png",
            "README.md",
            "docs/ci-cd-guardrails.md",
            "screenshots/iphone/01.png",
            "TWAQI/Resources/intro.mp4",
            ".github/pull_request_template.md",
        )
        self.assertEqual(result.level, level.SKIP)
        self.assertEqual(len(result.files), 9)

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
            "Podfile",
            "Podfile.lock",
            "TWAQI.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            "tools/ci_test_level.py",
            "tools/test_ci_test_level.py",
        ):
            with self.subTest(path=path):
                self.assertEqual(decide(path).level, level.TEST)

    def test_a_view_change_builds(self):
        result = decide("TWAQI/Views/Forecast/ForecastView.swift", "README.md")
        self.assertEqual(result.level, level.BUILD)
        self.assertEqual(result.files, ["TWAQI/Views/Forecast/ForecastView.swift"])

    def test_other_app_paths_build(self):
        for path in (
            "TWAQI.xcodeproj/project.pbxproj",
            "TWAQI/Localization/en.lproj/Localizable.strings",
            "TWAQI/Assets.xcassets/AppIcon.appiconset/Contents.json",
            "TWAQIWidget/TWAQIWidget.swift",
            "TWAQIWatch/ContentView.swift",
            "TWAQIVision/Favourites.swift",
            "TWAQITests/StationParsingTests.swift",
            "tools/pr_policy.py",
        ):
            with self.subTest(path=path):
                self.assertEqual(decide(path).level, level.BUILD)

    def test_a_guarded_file_tests(self):
        for path in (
            "TWAQI/Utils/PushService.swift",
            "TWAQI/Utils/StationCamFrameCache.swift",
            "TWAQI/Views/Details/StationCamView.swift",
            "TWAQITests/PushServiceTests.swift",
        ):
            with self.subTest(path=path):
                self.assertEqual(decide(path).level, level.TEST)

    def test_mixed_list_highest_level_wins(self):
        result = decide(
            "workers/twaqi-workers/src/forecast.ts",
            "TWAQI/ContentView.swift",
            "TWAQI/Utils/PushService.swift",
            "README.md",
        )
        self.assertEqual(result.level, level.TEST)
        self.assertEqual(result.files, ["TWAQI/Utils/PushService.swift"])
        result = decide("workers/twaqi-workers/src/forecast.ts", "TWAQI/ContentView.swift")
        self.assertEqual(result.level, level.BUILD)
        self.assertEqual(result.files, ["TWAQI/ContentView.swift"])

    def test_empty_list_tests(self):
        self.assertEqual(decide().level, level.TEST)
        self.assertEqual(decide("", "  ").level, level.TEST)

    def test_api_error_tests(self):
        self.assertEqual(decide("README.md", api_error=True).level, level.TEST)

    def test_the_label_forces_test(self):
        self.assertEqual(decide("README.md", labels=["ci-full-tests"]).level, level.TEST)
        self.assertEqual(decide("README.md", labels=["documentation"]).level, level.SKIP)

    def test_paths_are_normalized_and_case_insensitive(self):
        self.assertEqual(decide("./TWAQI/Utils/pushservice.swift").level, level.TEST)
        self.assertEqual(decide("Docs/NOTES.MD").level, level.SKIP)


class GlobTests(unittest.TestCase):
    def test_star_stays_in_one_segment(self):
        self.assertTrue(level.matches("TWAQI/Utils/StationCamStore.swift", ["TWAQI/Utils/StationCam*.swift"]))
        self.assertFalse(level.matches("TWAQI/Utils/Sub/StationCam.swift", ["TWAQI/Utils/StationCam*.swift"]))

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
            (root / "TWAQITests").mkdir()
            (root / "TWAQI").mkdir()
            (root / "TWAQI/A.swift").write_text("")
            (root / "TWAQITests/ATests.swift").write_text("final class ATests: XCTestCase {}\n")
            (root / "TWAQITests/BTests.swift").write_text("final class BTests: XCTestCase {}\n")
            in_step = level.check(root, ["ATests"], ["TWAQI/A.swift", "TWAQITests/ATests.swift"])
            self.assertEqual(in_step, [])
            problems = level.check(root, ["ATests", "BTests", "CTests"], ["TWAQI/A.swift", "TWAQI/Gone.swift", "TWAQITests/ATests.swift"])
            self.assertEqual(len(problems), 3, problems)
            self.assertTrue(any("TWAQI/Gone.swift" in problem for problem in problems))
            self.assertTrue(any("BTests lives in TWAQITests/BTests.swift" in problem for problem in problems))
            self.assertTrue(any("CTests" in problem for problem in problems))


class RepositoryTests(unittest.TestCase):
    """The real lists in ci.yml against this checkout."""

    def test_ci_yml_lists_are_in_step(self):
        suites, guarded = level.load_lists(ROOT / level.WORKFLOW)
        self.assertEqual(level.check(ROOT, suites, guarded), [])

    def test_ci_yml_guards_each_area_from_the_ticket(self):
        _, guarded = level.load_lists(ROOT / level.WORKFLOW)
        for path in (
            "TWAQI/Utils/PollutantCache.swift",
            "TWAQI/Utils/OfflineCacheRetention.swift",
            "TWAQI/Utils/PushService.swift",
            "TWAQI/Utils/DirectusPushMirror.swift",  # OneSignalTags lives here
            "TWAQI/Utils/FavouriteAlerts.swift",
            "TWAQI/Utils/StationCamHistoryCache.swift",
            "TWAQI/Utils/SettingsStore.swift",
        ):
            with self.subTest(path=path):
                self.assertEqual(level.classify(path, guarded), level.TEST)


if __name__ == "__main__":
    unittest.main()
