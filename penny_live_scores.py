# Interim view of a running penny job: run ON THE NODE (ssh gnodeNNN while the job is alive).
# Reads the live WAL database through the sqlite backup API; a plain cp of talent.db misses the -wal file.
# Usage: LD_LIBRARY_PATH=/software/apps/u22/python/3.12.15/lib /scratch/nishanth.r/penny/.venv/bin/python -I penny_live_scores.py
import sqlite3, json
live = sqlite3.connect("file:/scratch/nishanth.r/penny/data/talent.db?mode=ro", uri=True, timeout=60)
con = sqlite3.connect(":memory:"); live.backup(con); live.close(); con.row_factory = sqlite3.Row
run = con.execute("select run_id from runs where stage='pipeline' order by run_id desc limit 1").fetchone()[0]
print("latest pipeline run:", run)
rows = con.execute("select company_id,total,coverage,explain from scores where run_id=? order by total desc", (run,)).fetchall()
print("scored so far:", len(rows))
for r in rows:
    n = con.execute("select count(*) from people where company_id=?", (r["company_id"],)).fetchone()[0]
    ex = r["explain"] or ""
    try: ex = json.loads(ex)
    except Exception: pass
    flags = [w for w in (ex.get("integrity") if isinstance(ex, dict) else []) if w.startswith("-")] if isinstance(ex, dict) else []
    print(f'{r["company_id"]:18s} total={r["total"]:6.1f} coverage={r["coverage"]:.2f} people={n:3d} {flags}')
print("people total:", con.execute("select count(*) from people").fetchone()[0], " documents:", con.execute("select count(*) from documents").fetchone()[0])
