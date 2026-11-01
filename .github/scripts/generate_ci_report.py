#!/usr/bin/env python3
"""
generate_ci_report.py
Generates Markdown test report, coverage breakdown, PR comment and a self-contained
HTML report for Horizon CI.
"""

import os
import sys
import json
import hashlib
import re
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from report_html import render_html

def get_file_sha256(filepath):
    if not os.path.exists(filepath):
        return None
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(8192):
            h.update(chunk)
    return h.hexdigest()

def get_file_size_mb(filepath):
    if not os.path.exists(filepath):
        return None
    size_bytes = os.path.getsize(filepath)
    return round(size_bytes / (1024 * 1024), 2)

def parse_test_log(log_path):
    summary = {
        "passed": 0,
        "failed": 0,
        "total": 0,
        "duration": "N/A",
        "suites": {},
        "issues": [],
        "status": "UNKNOWN"
    }

    if not os.path.exists(log_path):
        return summary

    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    # --- XCTest summary -------------------------------------------------------------
    # "Executed 2 tests, with 0 failures (0 unexpected) in 0.045 (0.046) seconds"
    # With only Swift Testing tests this line still appears, as "Executed 0 tests".
    xc_total = xc_failed = 0
    xc_duration = None
    for m in re.finditer(
        r"Executed\s+(\d+)\s+tests?,\s+with\s+(\d+)\s+failures?.*?in\s+([\d\.]+)\s+\(([\d\.]+)\)\s+seconds",
        content,
    ):
        xc_total += int(m.group(1))
        xc_failed += int(m.group(2))
        xc_duration = m.group(1) and m.group(3)

    # --- Swift Testing summary ------------------------------------------------------
    # "✔ Test run with 152 tests in 14 suites passed after 27.425 seconds."
    # "✘ Test run with 152 tests in 14 suites failed after 59.5 seconds with 3 issues."
    st_total = 0
    st_failed = 0
    st_duration = None
    run_matches = re.findall(
        r"Test run with\s+(\d+)\s+tests?(?:\s+in\s+\d+\s+suites?)?\s+(passed|failed)\s+after\s+([\d\.]+)\s+seconds(?:\s+with\s+(\d+)\s+issues?)?",
        content,
    )
    for total, outcome, secs, issues in run_matches:
        st_total += int(total)
        st_duration = secs
        if outcome == "failed":
            # Number of failed tests is derived from the per-test lines below;
            # fall back to the issue count if none could be parsed.
            st_failed = max(st_failed, 1)

    # --- Individual test results ----------------------------------------------------
    # XCTest:         Test Case '-[HorizonTests testRemoteNameSanitization]' passed (0.002 seconds)
    # Swift Testing:  ✔ Test testRemoteNameSanitization() passed after 0.001 seconds.
    #                 ✘ Test "parameterized name" with 3 test cases failed after 0.01 seconds with 1 issue.
    case_re = re.compile(
        r"Test (?:Case ['\"]-\[(\w+)\s+(\w+)\]['\"]|(\w+)\(\)|\"([^\"]+)\"\s+with\s+\d+\s+test\s+cases?)"
        r"\s+(passed|failed)(?:\s+after\s+([\d\.]+)\s+seconds|\s+\(([\d\.]+)\s+seconds\))?"
    )
    seen = set()
    st_failed_cases = 0
    for tc in case_re.finditer(content):
        suite = tc.group(1) or "SwiftTesting"
        name = tc.group(2) or tc.group(3) or tc.group(4)
        res = tc.group(5)
        secs = tc.group(6) or tc.group(7)
        if tc.group(1):
            # XCTest can echo a case more than once; Swift Testing names may legitimately
            # repeat across suites, so only de-duplicate XCTest cases.
            key = (suite, name, res)
            if key in seen:
                continue
            seen.add(key)
        summary["suites"].setdefault(suite, []).append({
            "name": name,
            "status": res.upper(),
            "duration": float(secs) if secs else None,
        })
        if not tc.group(1) and res == "failed":
            st_failed_cases += 1

    # --- Failure details ------------------------------------------------------------
    # Swift Testing: ✘ Test foo() recorded an issue at File.swift:12:13: Expectation failed: a == b
    # XCTest:        /path/File.swift:12: error: -[Class test] : XCTAssertEqual failed ...
    for m in re.finditer(
        r"✘ Test (.+?) recorded an issue(?: at (.+?:\d+)(?::\d+)?)?: (.*)", content
    ):
        summary["issues"].append({"test": m.group(1), "location": m.group(2) or "", "message": m.group(3).strip()})
    for m in re.finditer(r"^(\S+?\.swift:\d+): error: -\[(\w+ \w+)\] : (.*)$", content, re.M):
        summary["issues"].append({"test": m.group(2), "location": m.group(1), "message": m.group(3).strip()})

    if st_failed:
        st_failed = max(st_failed_cases, 1)

    summary["total"] = xc_total + st_total
    summary["failed"] = xc_failed + st_failed
    summary["passed"] = max(0, summary["total"] - summary["failed"])

    durations = [float(d) for d in (xc_duration, st_duration) if d is not None]
    if durations:
        # XCTest and Swift Testing run back to back, so the wall time is their sum.
        summary["duration"] = f"{sum(durations):.3f}s"

    if "** TEST SUCCEEDED **" in content:
        summary["status"] = "PASSED"
    elif "** TEST FAILED **" in content:
        summary["status"] = "FAILED"
    else:
        summary["status"] = "PASSED" if summary["failed"] == 0 and summary["total"] > 0 else "UNKNOWN"

    return summary

def parse_coverage(json_path, txt_path):
    coverage_info = {
        "overall_percentage": "N/A",
        "files": []
    }

    if os.path.exists(json_path):
        try:
            with open(json_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            line_cov = data.get("lineCoverage")
            if line_cov is not None:
                coverage_info["overall_percentage"] = f"{round(line_cov * 100, 1)}%"
                coverage_info["overall_pct"] = round(line_cov * 100, 1)

            targets = data.get("targets", [])
            for target in targets:
                target_name = target.get("name", "")
                for file_entry in target.get("files", []):
                    fname = file_entry.get("name", "")
                    cov = file_entry.get("lineCoverage", 0)
                    cov_pct = f"{round(cov * 100, 1)}%"
                    covered = file_entry.get("coveredLines", 0)
                    total = file_entry.get("executableLines", 0)
                    coverage_info["files"].append({
                        "target": target_name,
                        "file": fname,
                        "pct": round(cov * 100, 1),
                        "percentage": cov_pct,
                        "covered": covered,
                        "total": total
                    })
        except Exception as e:
            print(f"Error parsing coverage JSON: {e}")

    elif os.path.exists(txt_path):
        try:
            with open(txt_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
            for line in lines:
                match = re.search(r"(\S+\.swift)\s+(\d+\.\d+)%", line)
                if match:
                    coverage_info["files"].append({
                        "target": "Horizon",
                        "file": match.group(1),
                        "pct": float(match.group(2)),
                        "percentage": f"{match.group(2)}%",
                        "covered": "-",
                        "total": "-"
                    })
        except Exception:
            pass

    return coverage_info

def main():
    log_path = sys.argv[1] if len(sys.argv) > 1 else "test_build.log"
    cov_json_path = sys.argv[2] if len(sys.argv) > 2 else "coverage.json"
    cov_txt_path = sys.argv[3] if len(sys.argv) > 3 else "coverage_report.txt"
    dmg_path = sys.argv[4] if len(sys.argv) > 4 else "Horizon.dmg"

    test_summary = parse_test_log(log_path)
    cov_info = parse_coverage(cov_json_path, cov_txt_path)

    dmg_exists = os.path.exists(dmg_path)
    dmg_size = get_file_size_mb(dmg_path) if dmg_exists else None
    dmg_sha = get_file_sha256(dmg_path) if dmg_exists else None

    run_id = os.environ.get("GITHUB_RUN_ID", "")
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    commit_sha = os.environ.get("GITHUB_SHA", "")[:7]
    ref_name = os.environ.get("GITHUB_REF_NAME", "")
    server_url = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    run_url = f"{server_url}/{repo}/actions/runs/{run_id}" if repo and run_id else "#"

    overall_success = test_summary["status"] == "PASSED" and test_summary["failed"] == 0
    status_emoji = "✅" if overall_success else "❌"
    status_title = "Passed" if overall_success else "Failed"

    # Build PR Comment Markdown
    comment = []
    comment.append("<!-- horizon-ci-summary -->")
    comment.append(f"## {status_emoji} Horizon CI Pipeline {status_title}")
    comment.append(f"**Commit:** `{commit_sha}` | **Branch:** `{ref_name}` | **Run:** [#{run_id}]({run_url})\n")

    # Full report link. HTML_REPORT_URL is known only after the artifact upload, so the workflow
    # replaces this placeholder afterwards (it can also be provided directly via the environment).
    html_url = os.environ.get("HTML_REPORT_URL", "__HTML_REPORT_URL__")
    comment.append(f"### 🌐 [**Open the full interactive report**]({html_url})")
    comment.append("*Test list, failures, per-file coverage and build log in one page – no zip download needed.*\n")

    # DMG Artifact Section
    comment.append("### 📦 Built Installer (Apple Silicon DMG)")
    if dmg_exists:
        comment.append(f"- **Package:** `Horizon.dmg`")
        comment.append(f"- **Size:** `{dmg_size} MB`")
        comment.append(f"- **SHA-256:** `{dmg_sha}`")
        comment.append(f"- **Download:** [Download from Run Artifacts]({run_url})\n")
    else:
        comment.append("- ⚠️ *DMG build failed or not found.*\n")

    # Test Run Summary Section
    comment.append("### 🧪 Test Run Summary")
    comment.append("| Metric | Value |")
    comment.append("| :--- | :--- |")
    comment.append(f"| **Status** | {status_emoji} {test_summary['status']} |")
    comment.append(f"| **Total Tests** | `{test_summary['total']}` |")
    comment.append(f"| **Passed** | `{test_summary['passed']}` |")
    comment.append(f"| **Failed** | `{test_summary['failed']}` |")
    comment.append(f"| **Execution Time** | `{test_summary['duration']}` |\n")

    if test_summary["issues"]:
        comment.append("<details open><summary><b>Failures</b></summary>\n")
        for issue in test_summary["issues"][:25]:
            loc = f" (`{issue['location']}`)" if issue["location"] else ""
            comment.append(f"- **`{issue['test']}`**{loc}: {issue['message']}")
        if len(test_summary["issues"]) > 25:
            comment.append(f"- …and {len(test_summary['issues']) - 25} more – see the full report.")
        comment.append("\n</details>\n")

    if test_summary["suites"]:
        comment.append("<details><summary><b>View Individual Test Details</b></summary>\n")
        comment.append("| Suite | Test | Result |")
        comment.append("| :--- | :--- | :--- |")
        for suite, cases in test_summary["suites"].items():
            for c in cases:
                res_icon = "✅" if c["status"] == "PASSED" else "❌"
                comment.append(f"| `{suite}` | `{c['name']}` | {res_icon} {c['status']} |")
        comment.append("\n</details>\n")

    # Test Coverage Section
    comment.append("### 📊 Code Coverage")
    comment.append(f"**Overall Line Coverage:** `{cov_info['overall_percentage']}`\n")
    if cov_info["files"]:
        comment.append("<details><summary><b>Coverage by Source File</b></summary>\n")
        comment.append("| File | Coverage | Covered / Executable Lines |")
        comment.append("| :--- | :--- | :--- |")
        for f in cov_info["files"]:
            comment.append(f"| `{f['file']}` | **{f['percentage']}** | `{f['covered']}/{f['total']}` |")
        comment.append("\n</details>\n")

    # Artifacts Section
    comment.append("---")
    comment.append("### 📁 Workflow Artifacts Available")
    comment.append(f"1. **`Horizon-macOS-DMG`**: Contains `Horizon.dmg` ready for testing on macOS.")
    comment.append(f"2. **`Horizon-Test-Report`**: Contains `test_report.md`, `coverage_report.txt`, and `TestResults.xcresult` bundle.")
    comment.append(f"\n*Uploaded to workflow run: [View Artifacts]({run_url})*")

    pr_comment_content = "\n".join(comment)

    # Write PR comment file
    with open("pr_comment.md", "w", encoding="utf-8") as f:
        f.write(pr_comment_content)

    # Write Standalone Test Report file
    with open("test_report.md", "w", encoding="utf-8") as f:
        f.write(pr_comment_content)

    # Write the self-contained HTML report
    html = render_html(
        test_summary,
        cov_info,
        {
            "commit": commit_sha,
            "branch": ref_name,
            "run_id": run_id,
            "run_url": run_url,
            "repo": repo,
            "dmg": {"size": dmg_size, "sha": dmg_sha} if dmg_exists else None,
            "log_path": log_path,
            "generated": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        },
    )
    with open("test_report.html", "w", encoding="utf-8") as f:
        f.write(html)

    print("Generated pr_comment.md, test_report.md and test_report.html successfully.")

if __name__ == "__main__":
    main()

