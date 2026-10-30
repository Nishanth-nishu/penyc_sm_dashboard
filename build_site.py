#!/usr/bin/env python3
"""Build the GitHub Pages site (docs/) from one penny_results/<job> folder.

    python3 build_site.py penny_results/46482            # writes docs/
    python3 build_site.py penny_results/47116 --out docs

Produces index.html (run summary + leaderboard), overviews.html (all company overviews, searchable),
dashboard.html (the pipeline's own interactive board, copied as is), scores.csv and overviews.json.
Run metadata (node, model, start/end) is read from logs/penny_<job>.log when it is present.
"""
from __future__ import annotations
import argparse, csv, html, json, re, shutil
from pathlib import Path

CSS = """
:root { --bg:#f6f7f4; --card:#fff; --fg:#15181a; --fg2:#5a615e; --line:#d9ddd9; --accent:#2a78d6; --weak:#e34948; --mid:#eda100; --strong:#1baf7a; }
@media (prefers-color-scheme: dark) { :root { --bg:#131516; --card:#1d2022; --fg:#e8eae7; --fg2:#a2a8a5; --line:#33383a; --accent:#6aa6ef; } }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.5 -apple-system, "Segoe UI", Roboto, sans-serif; }
main { max-width: 1040px; margin: 0 auto; padding: 24px 16px 64px; }
h1 { font-size: 1.7rem; margin: 0 0 4px; } h2 { font-size: 1.2rem; margin: 32px 0 8px; }
.sub { color: var(--fg2); margin: 0 0 16px; }
nav a { margin-right: 18px; color: var(--accent); text-decoration: none; font-weight: 600; }
.stats { display:grid; grid-template-columns: repeat(auto-fit, minmax(150px,1fr)); gap:12px; margin:16px 0; }
.stat { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:12px 14px; }
.stat b { display:block; font-size:1.5rem; } .stat span { color:var(--fg2); font-size:.9rem; }
table { width:100%; border-collapse: collapse; background:var(--card); border:1px solid var(--line); border-radius:10px; overflow:hidden; font-size:.95rem; }
th, td { padding: 8px 10px; text-align:left; border-bottom:1px solid var(--line); } th { color:var(--fg2); font-weight:600; }
td.num { text-align:right; font-variant-numeric: tabular-nums; }
.pill { display:inline-block; padding:1px 8px; border-radius:999px; font-size:.8rem; color:#fff; }
.weak { background:var(--weak);} .middling { background:var(--mid);} .strong { background:var(--strong);}
.card { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:14px 16px; margin:12px 0; }
.card h3 { margin:0 0 2px; font-size:1.05rem; } .meta { color:var(--fg2); font-size:.88rem; margin-bottom:8px; }
.card p { margin: 0; } .card a { color: var(--accent); }
input[type=search] { width:100%; padding:10px 12px; font-size:1rem; border:1px solid var(--line); border-radius:8px; background:var(--card); color:var(--fg); margin:8px 0 16px; }
.note { background:var(--card); border-left:4px solid var(--mid); padding:10px 14px; border-radius:6px; color:var(--fg2); font-size:.92rem; }
@media (max-width:600px) { th:nth-child(5), td:nth-child(5) { display:none; } }
"""

def band(x):
    return "strong" if x > 50 else "middling" if x >= 25 else "weak"

def run_meta(job: str) -> dict:
    log = Path("logs") / f"penny_{job}.log"
    m = {"job": job}
    if not log.exists():
        return m
    txt = log.read_text(errors="replace")
    if g := re.search(r"job \d+ on (\S+) \| mode=(\S+) model=(\S+)", txt): m.update(node=g[1], mode=g[2], model=g[3])
    if g := re.search(r"start: (\S+ \S+) UTC / (\S+) IST", txt): m.update(start_utc=g[1], start_ist=g[2])
    if g := re.search(r"DONE (\S+ \S+) UTC / (\S+) IST", txt): m.update(end_utc=g[1], end_ist=g[2])
    m["skipped"] = len(re.findall(r"ERROR talent\.stages\.pipeline: \S+ failed", txt))
    return m

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results"); ap.add_argument("--out", default="docs")
    a = ap.parse_args()
    res, out = Path(a.results), Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    job = res.name
    meta = run_meta(job)
    rows = list(csv.DictReader(open(res / "export/scores.csv")))
    for r in rows:
        r["score_f"] = float(r["score"] or 0); r["cov_f"] = float(r["coverage"] or 0); r["people_i"] = int(float(r["named_people"] or 0))
    rows.sort(key=lambda r: -r["score_f"])
    ovs = json.load(open(res / "overviews.json"))
    ov_by = {o["company_id"]: o for o in ovs}
    with_people = sum(r["people_i"] > 0 for r in rows)
    bands = {b: sum(band(r["score_f"]) == b for r in rows) for b in ("weak", "middling", "strong")}
    gc = sum(r["going_concern"] in ("True", "true", "1") for r in rows)
    rm = sum(r["reverse_merger"] in ("True", "true", "1") for r in rows)
    e = html.escape

    # copies
    shutil.copy(res / "dashboard.html", out / "dashboard.html")
    shutil.copy(res / "export/scores.csv", out / "scores.csv")
    shutil.copy(res / "overviews.json", out / "overviews.json")
    (out / ".nojekyll").write_text("")

    when = f'{meta.get("start_utc","?")} UTC ({meta.get("start_ist","?")} IST) to {meta.get("end_utc","?")} UTC ({meta.get("end_ist","?")} IST)' if "start_utc" in meta else "see PENNY_RESULTS.md"
    head = lambda title: f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{e(title)}</title><style>{CSS}</style></head><body><main>'
    nav = '<nav><a href="index.html">Summary</a><a href="dashboard.html">Interactive dashboard</a><a href="overviews.html">Company overviews</a><a href="scores.csv">scores.csv</a><a href="https://github.com/Nishanth-nishu/penyc_sm_dashboard/blob/main/PENNY_RESULTS.md">Run notes</a></nav>'

    # index
    top = "".join(
        f'<tr><td>{e(r["market"])}</td><td><a href="overviews.html#{e(r["market"])}-{e(r["ticker"])}">{e(r["ticker"])}</a></td><td>{e(r["name"])}</td>'
        f'<td class="num">{r["score_f"]:.1f} <span class="pill {band(r["score_f"])}">{band(r["score_f"])}</span></td>'
        f'<td class="num">{r["cov_f"]:.2f}</td><td class="num">{r["people_i"]}</td></tr>' for r in rows[:20])
    idx = head("Penny Talent Results") + f'''
<h1>Penny-stock talent screen</h1>
<p class="sub">Job {e(job)} on {e(meta.get("node","the Ada cluster"))}, model {e(meta.get("model","llama3.1:8b"))} via local Ollama. {e(when)}.{" This job reran the companies that failed in the full run, on top of that run's database; the numbers below cover all 100." if meta.get("mode")=="rerun" else ""}</p>
{nav}
<div class="stats">
<div class="stat"><b>{sum(1 for r in rows if r.get("score"))}</b><span>companies scored (of {len(rows)})</span></div>
<div class="stat"><b>{with_people}</b><span>with named people</span></div>
<div class="stat"><b>{meta.get("skipped","-")}</b><span>skipped by errors</span></div>
<div class="stat"><b>{bands["weak"]} / {bands["middling"]} / {bands["strong"]}</b><span>weak / middling / strong</span></div>
<div class="stat"><b>{gc}</b><span>going-concern flags</span></div>
<div class="stat"><b>{rm}</b><span>reverse-merger flags</span></div>
</div>
<p class="note">Scores come from an 8-billion-parameter model reading microcap filings on an 11 GB GPU. Every company lands in the weak band (below 25) and the ranking is driven mostly by hiring and headcount momentum; treat it as a screen, not a verdict. Coverage is the fraction of the workforce the score actually saw.</p>
<h2>Top 20 by talent score</h2>
<table><thead><tr><th>Market</th><th>Ticker</th><th>Company</th><th>Score</th><th>Coverage</th><th>People</th></tr></thead><tbody>{top}</tbody></table>
<p class="sub" style="margin-top:12px">Full ranking with component breakdowns and flags: <a href="dashboard.html">interactive dashboard</a> or <a href="scores.csv">scores.csv</a>.</p>
</main></body></html>'''
    (out / "index.html").write_text(idx)

    # overviews
    cards = []
    for r in rows:
        o = ov_by.get(r["market"] + ":" + r["ticker"]) or {}
        f = o.get("facts") or {}
        site = f.get("website") or r.get("website") or ""
        site_html = f' · <a href="{e(site)}" rel="noopener">website</a>' if site.startswith("http") else ""
        cards.append(f'''<article class="card" id="{e(r["market"])}-{e(r["ticker"])}" data-text="{e((r["name"] + " " + r["ticker"] + " " + (o.get("overview") or "")).lower())}">
<h3>{e(r["name"])} <span class="pill {band(r["score_f"])}">{r["score_f"]:.1f}</span></h3>
<div class="meta">{e(r["market"].upper())} · {e(r["ticker"])} · {e(r.get("exchange") or "")} · {e(r.get("sector") or "")} · coverage {r["cov_f"]:.2f} · {r["people_i"]} named people{site_html}</div>
<p>{e(o.get("overview") or "No overview was generated for this company.")}</p></article>''')
    ovp = head("Company Overviews") + f'''
<h1>Company overviews</h1>
<p class="sub">{len(cards)} companies from job {e(job)}, sorted by talent score. Each paragraph was written by {e(meta.get("model","llama3.1:8b"))} from the pipeline's facts only.</p>
{nav}
<input type="search" id="q" placeholder="Filter by name, ticker or text" aria-label="Filter companies">
<div id="list">{"".join(cards)}</div>
<script>
const q=document.getElementById('q'), cards=[...document.querySelectorAll('.card')];
q.addEventListener('input',()=>{{const s=q.value.trim().toLowerCase(); cards.forEach(c=>c.style.display=!s||c.dataset.text.includes(s)?'':'none');}});
</script>
</main></body></html>'''
    (out / "overviews.html").write_text(ovp)
    print(f"wrote {out}/ from {res}: {len(rows)} companies, {len(cards)} overviews")

if __name__ == "__main__":
    main()
