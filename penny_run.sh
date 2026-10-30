#!/bin/bash
#SBATCH -A plafnet2
#SBATCH -p plafnet2
#SBATCH -J penny_talent
#SBATCH -n 10
#SBATCH --gres=gpu:1
#SBATCH --mem-per-cpu=3G
#SBATCH --time=1-00:00:00
#SBATCH --nodelist=gnode114
#SBATCH --output=/home2/nishanth.r/penyc_sm_dashboard/logs/penny_%j.log
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=nishanth0962333@gmail.com
#
# Penny-stock talent pipeline on gnode114 with local Ollama extraction.
#
#   sbatch penny_run.sh                                   # pilot: 2 tickers
#   PENNY_MODE=full sbatch penny_run.sh                   # all 100 companies
#   PENNY_TICKERS="PDSB india:NHCFOODS" sbatch penny_run.sh
#   PENNY_MODEL=llama3.1:8b PENNY_MODE=full sbatch penny_run.sh
#   PENNY_NUM_CTX=32768 sbatch penny_run.sh                # on a 24 GB card
#   PENNY_SEARCH=0 sbatch penny_run.sh                      # no SearXNG / web search (filings + site only)
#   PENNY_MODE=rerun PENNY_TICKERS="BKYI india:A1L" PENNY_RESTORE_DB=penny_results/47396/talent.db \
#       PENNY_OLLAMA_TIMEOUT=180 PENNY_CHUNK_CHARS=15000 sbatch penny_run.sh         # redo some companies on top of an earlier DB,
#                                                            # then refresh export + overviews for everyone
#
# plafnet2 (gnode113-118) is out of GPU-minutes until ~1 Nov 2026; until then run on the
# general partition with the plafnet account:
#   sbatch -A plafnet -p u22 --qos=normal --nodelist= --gres=gpu:1 -n 10 penny_run.sh
#
# Repo source : /home2/nishanth.r/penyc_sm_dashboard/penny-stocks-investing  (git checkout, edit here)
# Work dir    : /scratch/nishanth.r/penny                        (venv, data/, caches; node-local)
# Results     : /home2/nishanth.r/penyc_sm_dashboard/penny_results/<jobid>/  (exports + overviews.md copied back every run)

set -o pipefail
SRC=/home2/nishanth.r/penyc_sm_dashboard/penny-stocks-investing
PROJ=${PENNY_PROJ:-/scratch/nishanth.r/penny}   # per-node work dir; override when two penny jobs may share a node
RESULTS=/home2/nishanth.r/penyc_sm_dashboard/penny_results/$SLURM_JOB_ID
MODE=${PENNY_MODE:-pilot}
TICKERS=${PENNY_TICKERS:-"PDSB india:NHCFOODS"}
MODEL=${PENNY_MODEL:-llama3.1:8b}
PY312=/software/apps/u22/python/3.12.15/bin/python3.12
export LD_LIBRARY_PATH=/software/apps/u22/python/3.12.15/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}   # python3.12 needs its libpython
NUM_CTX=${PENNY_NUM_CTX:-16384}   # 32768 in the repo default; 16k keeps llama3.1:8b inside an 11 GB card
OLLAMA_TIMEOUT=${PENNY_OLLAMA_TIMEOUT:-900}   # per-call cap; the 8B model sometimes loops on a chunk (15-25 min); normal calls take <40 s on a 1080 Ti, so 300 is safe
CHUNK_CHARS=${PENNY_CHUNK_CHARS:-40000}   # chars per Ollama extraction call; 15000 for companies whose 40k chunks make the model loop
LLM=${PENNY_LLM:-1}         # 0 = no Ollama/GPU: extraction provider none (search-layer tests on a CPU allocation)
SEARCH=${PENNY_SEARCH:-1}   # 1 = start a private SearXNG next to Ollama and use it for web search (0 = filings/site only)
RESTORE_DB=${PENNY_RESTORE_DB:-}   # talent.db from a previous results dir; always copied over scratch when set (node scratch may hold an older run)

echo "=========================================="
echo "PENNY TALENT | job $SLURM_JOB_ID on $SLURM_NODELIST | mode=$MODE model=$MODEL"
echo "start: $(date -u '+%F %T') UTC / $(TZ=Asia/Kolkata date '+%T') IST"
echo "=========================================="
nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free,utilization.gpu --format=csv,noheader 2>/dev/null || echo "no GPU (nvidia-smi unavailable)"

# ── 1. stage repo into scratch (keep data/ and .venv between runs: caches live there)
mkdir -p "$PROJ" "$RESULTS"
rsync -a --delete --exclude .venv --exclude data --exclude .env --exclude 'dashboard/index.html' "$SRC/" "$PROJ/"
cd "$PROJ" || exit 1
[ -f .env ] || cp .env.example .env
sed -i "s/^\(  ollama_num_ctx:\) *[0-9]*/\1 $NUM_CTX/; s/^\(  ollama_timeout_s:\) *[0-9]*/\1 $OLLAMA_TIMEOUT/; s/^\(  ollama_chunk_chars:\) *[0-9]*/\1 $CHUNK_CHARS/" config/sources.yaml
grep -nE 'ollama_num_ctx|ollama_timeout_s|ollama_chunk_chars' config/sources.yaml
if [ -n "$RESTORE_DB" ]; then
    [ "${RESTORE_DB:0:1}" = / ] || RESTORE_DB=/home2/nishanth.r/penyc_sm_dashboard/$RESTORE_DB
    mkdir -p data && rm -f data/talent.db-wal data/talent.db-shm && cp "$RESTORE_DB" data/talent.db && echo "restored DB from $RESTORE_DB"
fi

# ── 2. python 3.12 venv (repo needs >=3.11; node default is 3.10)
if [ -x "$PY312" ]; then PY=$PY312; else PY=$(command -v python3.12 || command -v python3.11 || command -v python3); fi
echo "base python: $PY ($($PY --version 2>&1))"
if [ ! -x .venv/bin/python ]; then
    "$PY" -m venv .venv || exit 1
fi
.venv/bin/python -m pip install -q --upgrade pip
.venv/bin/python -m pip install -q -e ".[dev]" || { echo "pip install failed"; exit 1; }
echo "venv python: $(.venv/bin/python --version)"

trap 'cp "$SCR/serve_${SLURM_JOB_ID}.log" "$RESULTS/ollama_serve.log" 2>/dev/null; cp "$SEARXNG_LOG" "$RESULTS/searxng.log" 2>/dev/null; type searxng_stop >/dev/null 2>&1 && searxng_stop; type ollama_sync_back >/dev/null 2>&1 && ollama_sync_back' EXIT   # keep the server logs: scratch dies with the job

# ── 3. Ollama from node scratch (skipped with PENNY_LLM=0)
if [ "$LLM" = 1 ]; then
source /home2/nishanth.r/penyc_sm_dashboard/ollama_env.sh "$MODEL" || exit 1
export TALENT_EXTRACTION_PROVIDER=ollama
export TALENT_OLLAMA_URL="http://$OLLAMA_HOST"
export TALENT_OLLAMA_MODEL="$MODEL"
else
export TALENT_EXTRACTION_PROVIDER=none
echo "PENNY_LLM=0: no Ollama; extraction provider none (people come from search snippets/regex only)"
fi
export PYTHONPATH="$PROJ/src"
talent() { "$PROJ/.venv/bin/python" -m talent.cli "$@"; }

# ── 3b. SearXNG (web search for people discovery, hidden documents, profile matching)
if [ "$SEARCH" = 1 ]; then
    source /home2/nishanth.r/penyc_sm_dashboard/searxng_env.sh || { echo "SearXNG failed to start; continuing without web search"; unset TALENT_SEARXNG_URL; }
else
    unset TALENT_SEARXNG_URL
fi

# ── 4. pipeline
stage() { echo; echo "────────── $1  ($(date -u +%T) UTC)"; }

if [ "$LLM" = 1 ]; then
stage "llm-check"
talent llm-check || exit 1
fi
if [ -n "$TALENT_SEARXNG_URL" ]; then
    stage "search-check"
    talent search-check || echo "search-check failed; web search parts will be skipped where unavailable"
fi
if [ "$MODE" = "pilot" ]; then
    stage "unit tests (offline)"
    .venv/bin/python -m pytest -q tests/test_websearch.py 2>&1 | tail -5
fi
if [ "$LLM" = 1 ]; then
# Job 47116 (gnode033) ran the whole pipeline at CPU speed (31 tok/s vs 329 on a 1080 Ti) and every call hit the
# timeout. Refuse to continue unless the model is fully on the GPU.
grep -iE 'inference compute|library=|no compatible|unable to load' "$SCR/serve_${SLURM_JOB_ID}.log" | head -5
ollama ps
if ! ollama ps | grep -qE '100% *GPU'; then
    echo "WARNING: $MODEL is not fully on the GPU ($(ollama ps | awk 'NR==2{print $4,$5}')) - expect ~10x slower inference"
    tail -30 "$SCR/serve_${SLURM_JOB_ID}.log"
    if [ "${PENNY_ALLOW_CPU:-0}" != 1 ]; then
        echo "aborting (exit 3). Resubmit with --exclude=$SLURM_NODELIST, or PENNY_ALLOW_CPU=1 to run anyway."
        exit 3
    fi
fi
fi   # LLM

if [ "$MODE" != "rerun" ]; then       # rerun keeps the universe already in the DB so the export stays comparable
    stage "universe build"
    talent universe build || exit 1
    talent universe show --limit 10
fi

if [ "$MODE" = "full" ]; then
    stage "run-all (all selected companies)"
    talent run-all
elif [ "$MODE" = "rerun" ]; then
    stage "run-all rerun: $TICKERS"
    ARGS=(); for t in $TICKERS; do ARGS+=(--ticker "$t"); done
    talent run-all "${ARGS[@]}"
else
    stage "run-all pilot: $TICKERS"
    ARGS=(); for t in $TICKERS; do ARGS+=(--ticker "$t"); done
    talent run-all "${ARGS[@]}"
    for t in $TICKERS; do
        stage "score --explain $t"; talent score "$t" --explain
        stage "people show $t";     talent people show "$t"
    done
fi

stage "status + export"
talent status
talent export

# ── 5. company overviews via the same Ollama server
if [ "$LLM" = 1 ]; then
stage "overview summaries"
if [ "$MODE" = "full" ] || [ "$MODE" = "rerun" ]; then ONLY=(); else ONLY=(--only); for t in $TICKERS; do case "$t" in india:*) ONLY+=("$t");; *) ONLY+=("us:$t");; esac; done; fi
PENNY_MODEL="$MODEL" .venv/bin/python /home2/nishanth.r/penyc_sm_dashboard/summarize_overviews.py --db data/talent.db --out "$RESULTS" "${ONLY[@]}"
else
echo "PENNY_LLM=0: overview summaries skipped"
fi

# ── 6. copy results home
cp -r data/export "$RESULTS/" 2>/dev/null
cp dashboard/index.html "$RESULTS/dashboard.html" 2>/dev/null
cp data/talent.db "$RESULTS/" 2>/dev/null
cp "$SCR/serve_${SLURM_JOB_ID}.log" "$RESULTS/ollama_serve.log" 2>/dev/null
du -sh "$RESULTS"; ls -la "$RESULTS"
echo "=========================================="
echo "DONE $(date -u '+%F %T') UTC / $(TZ=Asia/Kolkata date '+%T') IST  → $RESULTS"
echo "=========================================="
