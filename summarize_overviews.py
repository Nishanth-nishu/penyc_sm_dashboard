#!/usr/bin/env python3
"""Company overview summaries with a local Ollama model.

Reads the talent pipeline's SQLite DB (companies + people + latest scores), builds a compact
fact sheet per selected company and asks Ollama for a short plain-prose overview. Uses only
facts the pipeline collected; the prompt forbids inventing anything.

    python summarize_overviews.py --db /scratch/nishanth.r/penny/data/talent.db --out penny_results/<job>
Env: OLLAMA_HOST (host:port), PENNY_MODEL (model name). Outputs overviews.md and overviews.json.
"""
from __future__ import annotations
import argparse, json, os, sqlite3, sys, time
import httpx

PROMPT = """You write short company overviews for an investment-research notebook on penny stocks.
Using ONLY the facts below, write one paragraph of 4-6 sentences in plain prose (no bullet points, no headings):
what the company does and where it is listed, its size (price, market cap, headcount), who leads it and how
strong the team looks given the talent score and coverage, and any red flags. If a fact is missing say so briefly
instead of guessing. Do not add numbers or names that are not in the facts.

How to read the scores: talent_score_0_100 rates the quality of the people at the company (leadership, technical
bench, momentum, density, minus integrity penalties); below 25 is weak, 25-50 is middling, above 50 is strong.
coverage_0_1 is the fraction of the workforce the score actually saw (1.0 = everyone); low coverage means the score
is based on few people, not that analysts ignore the stock. Describe the score honestly using these bands.
The components are sub-scores: leadership, technical_bench, momentum and density run 0-100 (higher is better);
integrity_penalty is points deducted for red flags, so an integrity_penalty of 0 means no red flags were found
and is good news, not a warning. Only call something a red flag if it is listed as one in the facts.

FACTS
{facts}
"""


def latest_scores(con):
    run = con.execute("SELECT run_id FROM scores ORDER BY computed_at DESC LIMIT 1").fetchone()
    if not run:
        return {}
    return {r["company_id"]: dict(r) for r in con.execute(
        "SELECT company_id, total, coverage, components FROM scores WHERE run_id=?", (run[0],))}


def selected(con):
    run = con.execute("SELECT run_id FROM runs WHERE stage='universe' ORDER BY started_at DESC LIMIT 1").fetchone()
    if not run:
        return []
    return [r[0] for r in con.execute(
        "SELECT company_id FROM universe WHERE run_id=? AND selected=1 ORDER BY market, liquidity DESC", (run[0],))]


def facts_for(con, cid, score):
    row = con.execute("SELECT name, market, ticker, sector, exchange, json FROM companies WHERE company_id=?", (cid,)).fetchone()
    if not row:
        return None
    d = json.loads(row["json"] or "{}")
    bi, md, hc, reg = d.get("basic_info", {}) or {}, d.get("market_data", {}) or {}, d.get("headcount", {}) or {}, d.get("regulatory", {}) or {}
    ts = d.get("talent_score", {}) or {}
    people = con.execute("SELECT name, current_title, seniority FROM people WHERE company_id=? "
                         "ORDER BY CASE seniority WHEN 'founder' THEN 0 WHEN 'cxo' THEN 1 WHEN 'director' THEN 2 ELSE 3 END, name LIMIT 8",
                         (cid,)).fetchall()
    f = {
        "name": row["name"], "ticker": row["ticker"], "market": row["market"], "exchange": row["exchange"],
        "sector": row["sector"] or bi.get("sector"), "industry": bi.get("industry"),
        "description": (bi.get("description") or bi.get("summary") or bi.get("long_business_summary") or "")[:1200] or None,
        "website": bi.get("website") or d.get("website"),
        "price": md.get("price"), "currency": md.get("currency"), "market_cap": md.get("mcap") or md.get("market_cap"),
        "headcount": hc.get("total"), "headcount_as_of": hc.get("as_of"),
        "talent_score_0_100": (score or {}).get("total", ts.get("total")),
        "coverage_0_1": (score or {}).get("coverage", ts.get("coverage")),
        "score_components": json.loads(score["components"]) if score and isinstance(score.get("components"), str) else ts.get("components"),
        "red_flags": {k: v for k, v in reg.items() if v},
        "leadership": [f'{p["name"]} ({p["current_title"] or p["seniority"]})' for p in people] or None,
        "named_people_total": con.execute("SELECT COUNT(*) FROM people WHERE company_id=?", (cid,)).fetchone()[0],
    }
    return {k: v for k, v in f.items() if v not in (None, "", [], {})}


def ask(host, model, facts, timeout):
    body = {"model": model, "stream": False,
            "messages": [{"role": "user", "content": PROMPT.format(facts=json.dumps(facts, indent=1, ensure_ascii=False))}],
            "options": {"temperature": 0.2, "num_ctx": 8192}}
    r = httpx.post(f"http://{host}/api/chat", json=body, timeout=timeout)
    r.raise_for_status()
    return r.json()["message"]["content"].strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--model", default=os.environ.get("PENNY_MODEL", "llama3.1:8b"))
    ap.add_argument("--host", default=os.environ.get("OLLAMA_HOST", "127.0.0.1:11434"))
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--only", nargs="*", help="company_ids, e.g. us:PDSB india:NHCFOODS")
    ap.add_argument("--timeout", type=float, default=300)
    a = ap.parse_args()

    con = sqlite3.connect(a.db); con.row_factory = sqlite3.Row
    scores = latest_scores(con)
    ids = a.only or selected(con)
    if a.limit:
        ids = ids[: a.limit]
    os.makedirs(a.out, exist_ok=True)
    out = []
    t0 = time.time()
    for i, cid in enumerate(ids, 1):
        facts = facts_for(con, cid, scores.get(cid))
        if not facts:
            print(f"[{i}/{len(ids)}] {cid}: not in companies table, skipped", flush=True); continue
        try:
            text = ask(a.host, a.model, facts, a.timeout)
        except Exception as e:
            text = f"(summary failed: {e})"
        out.append({"company_id": cid, "ticker": facts.get("ticker"), "name": facts.get("name"), "market": facts.get("market"),
                    "talent_score": facts.get("talent_score_0_100"), "coverage": facts.get("coverage_0_1"), "overview": text, "facts": facts})
        print(f"[{i}/{len(ids)}] {cid}: {len(text)} chars  ({time.time()-t0:.0f}s)", flush=True)
    with open(os.path.join(a.out, "overviews.json"), "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    with open(os.path.join(a.out, "overviews.md"), "w") as f:
        f.write(f"# Company overviews ({a.model}, {len(out)} companies)\n\n")
        for o in out:
            sc = f" — talent {o['talent_score']:.1f}/100, coverage {o['coverage']:.2f}" if isinstance(o.get("talent_score"), (int, float)) and isinstance(o.get("coverage"), (int, float)) else ""
            f.write(f"## {o['market']}:{o['ticker']} {o['name']}{sc}\n\n{o['overview']}\n\n")
    print(f"wrote {len(out)} overviews to {a.out}/overviews.md", flush=True)


if __name__ == "__main__":
    main()
