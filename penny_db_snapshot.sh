#!/bin/bash
# Every 10 min, back up the live WAL database to /home2 so nothing is lost if the job hits its wall time.
# Started once per job via: scp penny_db_snapshot.sh gnodeNNN:/scratch/nishanth.r/ && ssh gnodeNNN "nohup /scratch/nishanth.r/snapshot.sh >/dev/null 2>&1 &"
# Edit OUT for the job id. The process is adopted into the job cgroup and dies with the job.
export LD_LIBRARY_PATH=/software/apps/u22/python/3.12.15/lib
OUT=/home2/nishanth.r/penyc_sm_dashboard/penny_results/46482/live
while [ -f /scratch/nishanth.r/penny/data/talent.db ]; do
  /scratch/nishanth.r/penny/.venv/bin/python -I - <<'PY'
import sqlite3, datetime
live = sqlite3.connect("file:/scratch/nishanth.r/penny/data/talent.db?mode=ro", uri=True, timeout=60)
dst = sqlite3.connect("/home2/nishanth.r/penyc_sm_dashboard/penny_results/46482/live/talent.db.tmp")
live.backup(dst); dst.close(); live.close()
import os; os.replace("/home2/nishanth.r/penyc_sm_dashboard/penny_results/46482/live/talent.db.tmp", "/home2/nishanth.r/penyc_sm_dashboard/penny_results/46482/live/talent.db")
print(datetime.datetime.now(datetime.timezone.utc).strftime("%H:%M UTC"), "snapshot ok")
PY
  sleep 600
done
