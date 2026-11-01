#!/usr/bin/env python3
"""
report_html.py
Renders the Horizon CI results as a single self-contained HTML page (no external
requests, so it also works behind a restrictive Content-Security-Policy).

The page is fully usable without JavaScript; JS only adds live filtering.
"""

from html import escape


def _pct_class(pct):
    if pct is None:
        return "na"
    if pct >= 80:
        return "good"
    if pct >= 50:
        return "warn"
    return "bad"


def _fmt_secs(value):
    if value is None:
        return "–"
    return f"{value * 1000:.0f} ms" if value < 1 else f"{value:.2f} s"


def _tail(path, max_lines):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    return "\n".join(lines[-max_lines:])


CSS = """
:root{
  --bg:#f6f7f9;--card:#fff;--text:#1b1f24;--muted:#5b6672;--line:#e2e6ea;--accent:#2563eb;
  --good:#1a7f37;--good-bg:#dcf5e3;--warn:#9a6700;--warn-bg:#fff3c4;--bad:#cf222e;--bad-bg:#ffe0e0;
  --code:#f0f2f5;
}
@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    --bg:#0e1116;--card:#161b22;--text:#e6edf3;--muted:#8b97a4;--line:#2a313a;--accent:#58a6ff;
    --good:#3fb950;--good-bg:#12301c;--warn:#d29922;--warn-bg:#3a2d0b;--bad:#f85149;--bad-bg:#3d1417;
    --code:#0d1117;
  }
}
:root[data-theme="dark"]{
  --bg:#0e1116;--card:#161b22;--text:#e6edf3;--muted:#8b97a4;--line:#2a313a;--accent:#58a6ff;
  --good:#3fb950;--good-bg:#12301c;--warn:#d29922;--warn-bg:#3a2d0b;--bad:#f85149;--bad-bg:#3d1417;
  --code:#0d1117;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);
  font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
a{color:var(--accent)}
.wrap{max-width:1080px;margin:0 auto;padding:0 16px 64px}
header{padding:28px 0 8px}
header h1{margin:0 0 4px;font-size:24px;letter-spacing:-.01em}
.meta{color:var(--muted);font-size:13px;display:flex;flex-wrap:wrap;gap:4px 16px}
.meta code{background:var(--code);padding:1px 6px;border-radius:5px}
nav{position:sticky;top:0;z-index:5;background:var(--bg);border-bottom:1px solid var(--line);
  margin:16px -16px 0;padding:8px 16px;display:flex;gap:16px;flex-wrap:wrap;font-size:14px}
nav a{text-decoration:none;color:var(--muted)}
nav a:hover{color:var(--accent)}
.banner{margin:20px 0;padding:14px 18px;border-radius:10px;font-weight:600;border:1px solid var(--line)}
.banner.good{background:var(--good-bg);color:var(--good)}
.banner.bad{background:var(--bad-bg);color:var(--bad)}
.banner.warn{background:var(--warn-bg);color:var(--warn)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:12px 0 4px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px}
.card .k{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.05em}
.card .v{font-size:26px;font-weight:650;margin-top:2px;font-variant-numeric:tabular-nums}
.card .v.good{color:var(--good)}.card .v.bad{color:var(--bad)}.card .v.warn{color:var(--warn)}
section{margin-top:36px}
h2{font-size:18px;margin:0 0 12px}
.panel{background:var(--card);border:1px solid var(--line);border-radius:10px;overflow:hidden}
table{width:100%;border-collapse:collapse;font-size:14px}
th,td{text-align:left;padding:8px 14px;border-bottom:1px solid var(--line);vertical-align:top}
tr:last-child td{border-bottom:0}
th{font-size:12px;color:var(--muted);text-transform:uppercase;letter-spacing:.05em;background:var(--card)}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
code,pre{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px}
pre{background:var(--code);padding:12px 14px;margin:0;overflow:auto;max-height:480px;white-space:pre}
.pill{display:inline-block;padding:1px 9px;border-radius:99px;font-size:12px;font-weight:600}
.pill.good{background:var(--good-bg);color:var(--good)}
.pill.bad{background:var(--bad-bg);color:var(--bad)}
.bar{display:inline-block;width:120px;height:8px;border-radius:99px;background:var(--line);
  vertical-align:middle;margin-right:8px;overflow:hidden}
.bar i{display:block;height:100%}
.bar i.good{background:var(--good)}.bar i.warn{background:var(--warn)}.bar i.bad{background:var(--bad)}
.tools{display:flex;gap:8px;padding:10px 14px;border-bottom:1px solid var(--line);flex-wrap:wrap}
.tools input,.tools select{font:inherit;padding:5px 9px;border:1px solid var(--line);border-radius:7px;
  background:var(--bg);color:var(--text)}
.tools input{flex:1;min-width:180px}
details{border-top:1px solid var(--line)}
details:first-child{border-top:0}
summary{cursor:pointer;padding:10px 14px;font-weight:600}
.issue{padding:10px 14px;border-bottom:1px solid var(--line)}
.issue:last-child{border-bottom:0}
.issue .loc{color:var(--muted);font-size:12px}
.empty{padding:16px 14px;color:var(--muted)}
.muted{color:var(--muted)}
footer{margin-top:40px;color:var(--muted);font-size:12px;text-align:center}
@media (max-width:640px){.bar{width:60px}}
"""

JS = """
(function(){
  var q=document.getElementById('tq'),s=document.getElementById('ts');
  if(!q||!s)return;
  var rows=[].slice.call(document.querySelectorAll('#tests tbody tr'));
  var count=document.getElementById('tcount');
  function apply(){
    var t=q.value.toLowerCase(),st=s.value,n=0;
    rows.forEach(function(r){
      var ok=(!t||r.dataset.name.indexOf(t)>-1)&&(!st||r.dataset.status===st);
      r.hidden=!ok; if(ok)n++;
    });
    if(count)count.textContent=n+' of '+rows.length+' shown';
  }
  q.addEventListener('input',apply);s.addEventListener('change',apply);apply();
})();
"""


def render_html(tests, coverage, meta):
    """
    tests:    dict from parse_test_log (total/passed/failed/duration/suites/issues/status)
    coverage: dict from parse_coverage  (overall_percentage/overall_pct/files)
    meta:     dict with commit, branch, run_id, run_url, repo, dmg (dict|None), log_path, generated
    """
    ok = tests["status"] == "PASSED" and tests["failed"] == 0
    unknown = tests["status"] == "UNKNOWN"
    banner_cls = "good" if ok else ("warn" if unknown else "bad")
    banner_txt = (
        "All tests passed" if ok
        else ("Test results could not be determined – see the log below" if unknown
              else f"{tests['failed']} test(s) failed")
    )

    overall_pct = coverage.get("overall_pct")
    cov_cls = _pct_class(overall_pct)

    out = []
    w = out.append
    w("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">")
    w("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">")
    w("<title>Horizon CI Report</title>")
    w(f"<style>{CSS}</style></head><body><div class=\"wrap\">")

    # Header
    w("<header><h1>Horizon CI Report</h1><div class=\"meta\">")
    if meta.get("commit"):
        w(f"<span>Commit <code>{escape(meta['commit'])}</code></span>")
    if meta.get("branch"):
        w(f"<span>Ref <code>{escape(meta['branch'])}</code></span>")
    if meta.get("run_id"):
        w(f"<span>Run <a href=\"{escape(meta['run_url'])}\">#{escape(str(meta['run_id']))}</a></span>")
    if meta.get("generated"):
        w(f"<span>Generated {escape(meta['generated'])}</span>")
    w("</div></header>")

    w("<nav><a href=\"#summary\">Summary</a>")
    if tests["issues"]:
        w("<a href=\"#failures\">Failures</a>")
    w("<a href=\"#tests\">Tests</a><a href=\"#coverage\">Coverage</a>"
      "<a href=\"#build\">Build</a><a href=\"#log\">Log</a></nav>")

    # Summary
    w("<section id=\"summary\">")
    w(f"<div class=\"banner {banner_cls}\">{escape(banner_txt)}</div>")
    w("<div class=\"cards\">")
    w(f"<div class=\"card\"><div class=\"k\">Status</div><div class=\"v {banner_cls}\">{escape(tests['status'].title())}</div></div>")
    w(f"<div class=\"card\"><div class=\"k\">Tests</div><div class=\"v\">{tests['total']}</div></div>")
    w(f"<div class=\"card\"><div class=\"k\">Passed</div><div class=\"v good\">{tests['passed']}</div></div>")
    w(f"<div class=\"card\"><div class=\"k\">Failed</div><div class=\"v {'bad' if tests['failed'] else ''}\">{tests['failed']}</div></div>")
    w(f"<div class=\"card\"><div class=\"k\">Duration</div><div class=\"v\">{escape(tests['duration'])}</div></div>")
    w(f"<div class=\"card\"><div class=\"k\">Line coverage</div><div class=\"v {cov_cls}\">{escape(coverage['overall_percentage'])}</div></div>")
    w("</div></section>")

    # Failures
    if tests["issues"]:
        w("<section id=\"failures\"><h2>Failures</h2><div class=\"panel\">")
        for issue in tests["issues"]:
            w("<div class=\"issue\">")
            w(f"<div><strong>{escape(issue['test'])}</strong></div>")
            if issue["location"]:
                w(f"<div class=\"loc\">{escape(issue['location'])}</div>")
            w(f"<pre style=\"margin-top:6px;max-height:none;white-space:pre-wrap\">{escape(issue['message'])}</pre>")
            w("</div>")
        w("</div></section>")

    # Tests
    rows = []
    for suite, cases in tests["suites"].items():
        for c in cases:
            rows.append((suite, c))
    w("<section id=\"tests\"><h2>Tests</h2><div class=\"panel\">")
    if rows:
        w("<div class=\"tools\"><input id=\"tq\" type=\"search\" placeholder=\"Filter by name…\" aria-label=\"Filter tests\">"
          "<select id=\"ts\" aria-label=\"Filter by result\"><option value=\"\">All results</option>"
          "<option value=\"PASSED\">Passed</option><option value=\"FAILED\">Failed</option></select>"
          f"<span id=\"tcount\" class=\"muted\" style=\"align-self:center\">{len(rows)} of {len(rows)} shown</span></div>")
        w("<table id=\"tests\"><thead><tr><th>Test</th><th>Suite</th><th class=\"num\">Time</th><th>Result</th></tr></thead><tbody>")
        # failed first, then slowest first
        rows.sort(key=lambda r: (r[1]["status"] != "FAILED", -(r[1].get("duration") or 0)))
        for suite, c in rows:
            cls = "good" if c["status"] == "PASSED" else "bad"
            w(f"<tr data-name=\"{escape(c['name'].lower(), quote=True)}\" data-status=\"{c['status']}\">"
              f"<td><code>{escape(c['name'])}</code></td><td class=\"muted\">{escape(suite)}</td>"
              f"<td class=\"num\">{_fmt_secs(c.get('duration'))}</td>"
              f"<td><span class=\"pill {cls}\">{c['status'].title()}</span></td></tr>")
        w("</tbody></table>")
        w("<div class=\"empty muted\" style=\"border-top:1px solid var(--line)\">"
          "Parameterized tests are listed once with all of their cases. Sorted: failures first, then slowest.</div>")
    else:
        w("<div class=\"empty\">No individual test results were found in the log.</div>")
    w("</div></section>")

    # Coverage
    w("<section id=\"coverage\"><h2>Code coverage</h2><div class=\"panel\">")
    files = coverage.get("files", [])
    if files:
        by_target = {}
        for f in files:
            by_target.setdefault(f["target"] or "(unknown)", []).append(f)
        for target, entries in by_target.items():
            covered = sum(e["covered"] for e in entries if isinstance(e["covered"], int))
            total = sum(e["total"] for e in entries if isinstance(e["total"], int))
            t_pct = round(100 * covered / total, 1) if total else None
            label = f"{escape(target)} &nbsp;<span class=\"muted\">{'' if t_pct is None else f'{t_pct}% · '}{covered}/{total} lines</span>" \
                if total else escape(target)
            w(f"<details{' open' if target.endswith('.app') else ''}><summary>{label}</summary>")
            w("<table><thead><tr><th>File</th><th>Coverage</th><th class=\"num\">Lines</th></tr></thead><tbody>")
            for e in sorted(entries, key=lambda e: (e["pct"], e["file"])):
                cls = _pct_class(e["pct"])
                w(f"<tr><td><code>{escape(e['file'])}</code></td>"
                  f"<td><span class=\"bar\"><i class=\"{cls}\" style=\"width:{min(100, e['pct'])}%\"></i></span>{e['pct']}%</td>"
                  f"<td class=\"num\">{e['covered']}/{e['total']}</td></tr>")
            w("</tbody></table></details>")
        w("<div class=\"empty muted\" style=\"border-top:1px solid var(--line)\">Files are sorted from least to most covered.</div>")
    else:
        w("<div class=\"empty\">No coverage data was produced.</div>")
    w("</div></section>")

    # Build
    w("<section id=\"build\"><h2>Build artifacts</h2><div class=\"panel\">")
    dmg = meta.get("dmg")
    if dmg:
        w("<table><tbody>"
          "<tr><th>Package</th><td><code>Horizon.dmg</code></td></tr>"
          f"<tr><th>Size</th><td>{escape(str(dmg['size']))} MB</td></tr>"
          f"<tr><th>SHA-256</th><td><code>{escape(dmg['sha'])}</code></td></tr>"
          f"<tr><th>Download</th><td><a href=\"{escape(meta['run_url'])}\">Workflow run artifacts</a> (<code>Horizon-macOS-DMG</code>)</td></tr>"
          "</tbody></table>")
    else:
        w("<div class=\"empty\">⚠️ The DMG was not built (tests failed or the build step did not succeed).</div>")
    w("</div></section>")

    # Log
    w("<section id=\"log\"><h2>Test &amp; build log</h2><div class=\"panel\">")
    tail = _tail(meta.get("log_path", ""), 400) if meta.get("log_path") else None
    if tail:
        w("<details open><summary>Last 400 lines of <code>test_build.log</code></summary>"
          f"<pre>{escape(tail)}</pre></details>")
    else:
        w("<div class=\"empty\">No log file was found.</div>")
    w("</div></section>")

    w("<footer>Generated by .github/scripts/generate_ci_report.py</footer>")
    w(f"</div><script>{JS}</script></body></html>")
    return "".join(out)
