#!/bin/bash
# Source this inside a SLURM job to run a private SearXNG metasearch instance on the
# node (loopback only), the way ollama_env.sh runs Ollama. The pipeline reaches it
# through TALENT_SEARXNG_URL (sources/websearch.py).
#
#   SRC  : /home2/nishanth.r/penyc_sm_dashboard/searxng      (git clone of searxng/searxng, git-ignored)
#   SCR  : /scratch/nishanth.r/searxng                       (venv + settings + logs; node-local, purged)
#   port : 30000 + (jobid % 10000), so two jobs on one node never collide
#
# Requires: python3.12 ($PY312) with LD_LIBRARY_PATH set (penny_run.sh does both), internet from the node.
# Exports : SEARXNG_URL, SEARXNG_PID, TALENT_SEARXNG_URL; defines searxng_stop.

SEARXNG_SRC=${SEARXNG_SRC:-/home2/nishanth.r/penyc_sm_dashboard/searxng}
SEARXNG_SCR=${SEARXNG_SCR:-/scratch/nishanth.r/searxng}
SEARXNG_PY=${PY:-${PY312:-python3}}
SEARXNG_PORT=$((30000 + ${SLURM_JOB_ID:-0} % 10000))
SEARXNG_TEMPLATE=${SEARXNG_TEMPLATE:-/home2/nishanth.r/penyc_sm_dashboard/searxng_settings.yml}

echo "[searxng_env] node=$(hostname) job=${SLURM_JOB_ID:-none} port=$SEARXNG_PORT"
if [ ! -f "$SEARXNG_SRC/searx/webapp.py" ]; then
    echo "[searxng_env] $SEARXNG_SRC is not a SearXNG checkout (git clone --depth 1 https://github.com/searxng/searxng.git)"; return 1 2>/dev/null || exit 1
fi
mkdir -p "$SEARXNG_SCR"
echo "[searxng_env] staging source -> $SEARXNG_SCR/src"
rsync -a --delete --exclude .git --exclude node_modules "$SEARXNG_SRC/" "$SEARXNG_SCR/src/"

# venv (kept between jobs on the same node; rebuilt when python changes)
if [ ! -x "$SEARXNG_SCR/.venv/bin/python" ] || ! "$SEARXNG_SCR/.venv/bin/python" -c 'import flask, lxml, msgspec, curl_cffi' 2>/dev/null; then
    echo "[searxng_env] building venv with $SEARXNG_PY"
    "$SEARXNG_PY" -m venv "$SEARXNG_SCR/.venv" || return 1 2>/dev/null || exit 1
    "$SEARXNG_SCR/.venv/bin/python" -m pip install -q --upgrade pip
    "$SEARXNG_SCR/.venv/bin/python" -m pip install -q -r "$SEARXNG_SCR/src/requirements.txt" || { echo "[searxng_env] pip install failed"; return 1 2>/dev/null || exit 1; }
fi

# settings: template with port + a per-job secret
SEARXNG_SETTINGS="$SEARXNG_SCR/settings_${SLURM_JOB_ID:-local}.yml"
SECRET=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
sed -e "s/__PORT__/$SEARXNG_PORT/" -e "s/__SECRET__/$SECRET/" "$SEARXNG_TEMPLATE" > "$SEARXNG_SETTINGS"

export SEARXNG_SETTINGS_PATH="$SEARXNG_SETTINGS"
export SEARXNG_LOG="$SEARXNG_SCR/searxng_${SLURM_JOB_ID:-local}.log"
( cd "$SEARXNG_SCR/src" && exec env PYTHONPATH="$SEARXNG_SCR/src" "$SEARXNG_SCR/.venv/bin/python" -m searx.webapp ) > "$SEARXNG_LOG" 2>&1 &
export SEARXNG_PID=$!
export SEARXNG_URL="http://127.0.0.1:$SEARXNG_PORT"
for i in $(seq 1 90); do
    curl -s -m 3 "$SEARXNG_URL/healthz" >/dev/null 2>&1 && break
    sleep 1
done
if ! curl -s -m 3 "$SEARXNG_URL/healthz" >/dev/null 2>&1; then
    echo "[searxng_env] server did not come up; log tail:"; tail -20 "$SEARXNG_LOG"; return 1 2>/dev/null || exit 1
fi
echo "[searxng_env] serve pid=$SEARXNG_PID url=$SEARXNG_URL settings=$SEARXNG_SETTINGS"
# one real query so the log shows which engines answer from this node
curl -s -m 25 "$SEARXNG_URL/search?q=Urja+Global+Limited+managing+director&format=json&language=en" \
  | "$SEARXNG_SCR/.venv/bin/python" -c 'import sys,json; d=json.load(sys.stdin); rs=d.get("results",[]); print("[searxng_env] test query:", len(rs), "results; engines:", sorted({e for r in rs for e in r.get("engines",[])})); print("[searxng_env] unresponsive:", d.get("unresponsive_engines"))' 2>&1 | head -3
export TALENT_SEARXNG_URL="$SEARXNG_URL"

searxng_stop() {
    kill "$SEARXNG_PID" 2>/dev/null
}
export -f searxng_stop
