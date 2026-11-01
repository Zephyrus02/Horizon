#!/usr/bin/env python3
"""Tests for generate_ci_report.py / report_html.py (run: python3 -m unittest discover -s .github/scripts)."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from generate_ci_report import parse_test_log, parse_coverage  # noqa: E402
from report_html import render_html  # noqa: E402

SWIFT_TESTING_PASS = """\
Test Suite 'All tests' passed at 2026-11-01 11:59:57.007.
\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
◇ Test run started.
✔ Test testRemoteNameSanitization() passed after 0.001 seconds.
✔ Test "parameterized one" with 3 test cases passed after 0.020 seconds.
✔ Test testAccountDatabaseOperations() passed after 0.004 seconds.
✔ Test run with 3 tests in 1 suite passed after 0.030 seconds.
** TEST SUCCEEDED **
"""

SWIFT_TESTING_FAIL = """\
✘ Test brokenThing() recorded an issue at Foo.swift:12:9: Expectation failed: a == b
✘ Test brokenThing() failed after 0.5 seconds with 1 issue.
✔ Test fine() passed after 0.001 seconds.
✘ Test run with 2 tests in 1 suite failed after 0.6 seconds with 1 issue.
** TEST FAILED **
"""

XCTEST = """\
Test Case '-[HorizonTests testA]' passed (0.002 seconds).
Test Case '-[HorizonTests testB]' failed (0.004 seconds).
/src/Foo.swift:44: error: -[HorizonTests testB] : XCTAssertEqual failed: ("1") is not equal to ("2")
\t Executed 2 tests, with 1 failures (1 unexpected) in 0.006 (0.007) seconds
** TEST FAILED **
"""


def parse(text):
    with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False, encoding="utf-8") as f:
        f.write(text)
    try:
        return parse_test_log(f.name)
    finally:
        os.unlink(f.name)


class ParseTestLog(unittest.TestCase):
    def test_swift_testing_run_is_counted_even_with_empty_xctest_summary(self):
        # Regression: CI used to report 0 tests because only "Executed N tests" was read.
        s = parse(SWIFT_TESTING_PASS)
        self.assertEqual((s["total"], s["passed"], s["failed"]), (3, 3, 0))
        self.assertEqual(s["status"], "PASSED")
        self.assertEqual(s["duration"], "0.030s")

    def test_individual_swift_testing_cases_and_durations(self):
        s = parse(SWIFT_TESTING_PASS)
        cases = {c["name"]: c for c in s["suites"]["SwiftTesting"]}
        self.assertEqual(set(cases), {"testRemoteNameSanitization", "parameterized one", "testAccountDatabaseOperations"})
        self.assertAlmostEqual(cases["testRemoteNameSanitization"]["duration"], 0.001)

    def test_failures_and_issue_details(self):
        s = parse(SWIFT_TESTING_FAIL)
        self.assertEqual(s["status"], "FAILED")
        self.assertEqual((s["total"], s["failed"], s["passed"]), (2, 1, 1))
        self.assertEqual(len(s["issues"]), 1)
        issue = s["issues"][0]
        self.assertEqual(issue["test"], "brokenThing()")
        self.assertEqual(issue["location"], "Foo.swift:12")
        self.assertIn("a == b", issue["message"])

    def test_xctest_is_still_supported(self):
        s = parse(XCTEST)
        self.assertEqual((s["total"], s["failed"], s["passed"]), (2, 1, 1))
        self.assertEqual(s["status"], "FAILED")
        self.assertEqual(s["issues"][0]["location"], "/src/Foo.swift:44")
        self.assertEqual({c["name"] for c in s["suites"]["HorizonTests"]}, {"testA", "testB"})

    def test_xcode16_parameterized_format_without_case_count(self):
        # Xcode 16.4 (GitHub's macos-15 runner) prints: ✔ Test "name" passed after 0.1 seconds.
        s = parse('✔ Test "renders each tab" passed after 1.350 seconds.\n✔ Test run with 1 tests passed after 1.4 seconds.\n')
        self.assertEqual([c["name"] for c in s["suites"]["SwiftTesting"]], ["renders each tab"])
        self.assertEqual(s["total"], 1)

    def test_same_test_name_in_two_suites_is_not_collapsed(self):
        s = parse("✔ Test preview() passed after 0.1 seconds.\n✔ Test preview() passed after 0.2 seconds.\n")
        self.assertEqual(len(s["suites"]["SwiftTesting"]), 2)

    def test_missing_log_is_unknown(self):
        s = parse_test_log("/definitely/not/here.log")
        self.assertEqual((s["total"], s["status"]), (0, "UNKNOWN"))


class ParseCoverage(unittest.TestCase):
    def test_json_has_numeric_percentages(self):
        import json
        data = {"lineCoverage": 0.937, "targets": [
            {"name": "Horizon.app", "files": [
                {"name": "A.swift", "lineCoverage": 0.5, "coveredLines": 5, "executableLines": 10}]}]}
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(data, f)
        try:
            c = parse_coverage(f.name, "/nope.txt")
        finally:
            os.unlink(f.name)
        self.assertEqual(c["overall_percentage"], "93.7%")
        self.assertEqual(c["overall_pct"], 93.7)
        self.assertEqual(c["files"][0]["pct"], 50.0)


class RenderHtml(unittest.TestCase):
    def render(self, log_text, **meta):
        tests = parse(log_text)
        cov = {"overall_percentage": "N/A", "files": []}
        base = {"commit": "abc1234", "branch": "7/merge", "run_id": "42", "run_url": "https://x/run/42",
                "repo": "o/r", "dmg": None, "log_path": "", "generated": "now"}
        base.update(meta)
        return render_html(tests, cov, base)

    def test_page_is_self_contained(self):
        page = self.render(SWIFT_TESTING_PASS)
        self.assertTrue(page.startswith("<!doctype html>"))
        self.assertNotIn("http://", page.replace("https://x/run/42", ""))
        self.assertNotIn("<link ", page)
        self.assertNotIn("<script src", page)
        self.assertIn("All tests passed", page)

    def test_failures_are_listed(self):
        page = self.render(SWIFT_TESTING_FAIL)
        self.assertIn("1 test(s) failed", page)
        self.assertIn("Foo.swift:12", page)
        self.assertIn('id="failures"', page)

    def test_untrusted_text_is_escaped(self):
        evil = "✘ Test t() recorded an issue at <img onerror=x>.swift:1:1: <script>alert(1)</script>\n"
        page = self.render(evil)
        self.assertIn("&lt;script&gt;alert(1)&lt;/script&gt;", page)   # proves the issue was rendered…
        self.assertNotIn("<script>alert(1)</script>", page)             # …and escaped
        self.assertNotIn("<img onerror", page)

    def test_log_tail_is_escaped_and_included(self):
        with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False, encoding="utf-8") as f:
            f.write("line <b>bold</b>\n")
        try:
            page = self.render(SWIFT_TESTING_PASS, log_path=f.name)
        finally:
            os.unlink(f.name)
        self.assertIn("line &lt;b&gt;bold&lt;/b&gt;", page)


if __name__ == "__main__":
    unittest.main()
