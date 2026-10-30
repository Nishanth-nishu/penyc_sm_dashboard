# Penny-stocks talent pipeline on Ada: handover

Last updated 2026-10-30 13:30 UTC (19:00 IST). Moved here from glycemico-pred on 30 Oct 2026; that repo keeps the commit history (1a5aa1e..1fabbf9) but none of the files. Written for whoever picks this up next,
human or Claude session. Everything here lives in this repo (`penyc_sm_dashboard`, folder
checked out at `/home2/nishanth.r/penyc_sm_dashboard` on the Ada login node) except the private
pipeline repo and the job outputs that are too big for git.

## 1. What this is

Run the private `penny-stocks-investing` pipeline ("talent" package, by TomatoChocolate12)
on the IIIT Ada HPC cluster with a local Ollama model instead of a paid LLM API, over 100
microcap companies (50 India, 50 US), then write a plain-prose overview of each company and
publish the results as a small website.

Pipeline stages per company: fetch filings, extract people and facts with the LLM, resolve
people, score (leadership, technical bench, momentum, density, integrity penalty), export.
Scores are 0-100; the pipeline's own bands are weak (<25), middling (25-50), strong (>50).

## 2. Current state

| | |
|---|---|
| Companies scored | 92 of 100 (job 47991 export), all in the weak band; top is Urja Global 23.2 |
| Companies with named people | 65 |
| Still skipped | 8: A1L, GATECH, GPRO, IPDN, TENX, XHG, XPON, DFDV (model loops on their first chunk even at 15000 chars; needs a `num_predict` cap in the pipeline, see PENNY_RESULTS.md) |
| Job in progress | none. Last: 47991 on gnode049 (30 Oct 08:09-09:04 UTC), recovered AMOD, JZ, ALEC |
| Website | **Live at https://penycsmdashboard.vercel.app/** (Vercel project `penyc_sm_dashboard`, team nishanth-nishus-projects, Git-connected to this repo). `vercel.json` serves `docs/` as a static site with no build step; every push to `main` redeploys in under a minute. GitHub Pages is not used. |
| Results note | `PENNY_RESULTS.md` (numbers, top 10, failure analysis, rerun history) |

## 3. Where things live

Repo files (this folder):

| File | Role |
|---|---|
| `penny_run.sh` | The sbatch job. Stages the pipeline into node scratch, builds a Python 3.12 venv, starts Ollama, runs the pipeline, writes overviews, copies results home. Modes: pilot (default), `PENNY_MODE=full`, `PENNY_MODE=rerun`. Env knobs: `PENNY_TICKERS`, `PENNY_MODEL`, `PENNY_NUM_CTX`, `PENNY_OLLAMA_TIMEOUT`, `PENNY_CHUNK_CHARS`, `PENNY_RESTORE_DB`, `PENNY_ALLOW_CPU`, `PENNY_SEARCH`. |
| `ollama_env.sh` | Sourced inside a job: extracts the Ollama release from `/home2/nishanth.r/ollama_persist` into `/scratch/nishanth.r/ollama`, rsyncs models, starts `ollama serve` on port `20000 + jobid % 10000`, syncs new models back on exit. |
| `ollama_node.sh` | Generic sbatch wrapper that just holds a GPU node with Ollama up (see `OLLAMA.md`). |
| `summarize_overviews.py` | Reads `talent.db`, sends each company's facts to Ollama `/api/chat`, writes `overviews.md` and `overviews.json`. The prompt defines the score bands and explains that integrity penalty 0 means no red flags. |
| `build_site.py` | `python3 build_site.py penny_results/<job> [--out docs]`: builds `docs/index.html` (stats, top 20), `docs/overviews.html` (all overviews, text filter), copies `dashboard.html`, `scores.csv`, `overviews.json`. Reads node, model, times and failure count from `logs/penny_<job>.log`. |
| `penny_live_scores.py` | Run on the node during a job: reads the live WAL database safely (sqlite backup API) and prints the current run's scores. |
| `penny_db_snapshot.sh` | nohup loop on the node: copies the live DB to `penny_results/<job>/live/` every 10 min (edit `OUT` for the job). Insurance against a job dying before it copies results home. |
| `PENNY_RESULTS.md` | Results and run history. |
| `OLLAMA.md` | Ollama-on-Ada notes. |
| `penny_results/<job>/` | `export/scores.csv`, `export/dashboard.json`, `dashboard.html`, `overviews.md/json`; `talent.db` and `ollama_serve.log` exist on the cluster but are git-ignored. Jobs: 46482 (full run), 47116 (failed rerun), 47396 (rerun), 47991 (rerun, most complete). |
| `docs/` | The website. |
| `logs/penny_<job>.log` | SLURM job logs (git-ignored, cluster only). |

Off-repo:

| Path | What |
|---|---|
| `/home2/nishanth.r/penyc_sm_dashboard/penny-stocks-investing` | Private clone, branch `ada-fixes` (local only, not pushed). Three fixes on top of upstream: SQLite write lock at the end of `run-all` (`stages/pipeline.py`: commit+close per-company connection; `db.py`: 60 s busy timeout, microsecond run ids); `sources/edgar.py` `employee_count` skipping non-numeric regex matches (crashed 7 US companies with `int('')`). |
| `/home2/nishanth.r/ollama_persist/` | `ollama-v0.40.12.tar.zst` plus `models/` (llama3.1:8b, llama3.2:3b). Home quota is 50 GB. |
| `/scratch/nishanth.r/penny` on a compute node | venv, `data/talent.db`, caches. Per node, purged after about 7-10 days. |

## 3a. Web search layer (SearXNG)

Added 30 Oct 2026. The pipeline's only broad source of *people* used to be filings and the
company's own site; 35 of 100 companies ended up with nobody named. Web search now fills that
gap through a **private SearXNG instance** (https://github.com/searxng/searxng, cloned at
`searxng/`, git-ignored) that each job starts on the node next to Ollama:

| Piece | What it does |
|---|---|
| `searxng_env.sh` | Sourced by `penny_run.sh` (unless `PENNY_SEARCH=0`): rsyncs the clone to `/scratch/nishanth.r/searxng/src`, builds a venv from its `requirements.txt`, renders `searxng_settings.yml` (JSON API on, limiter off, port `30000 + jobid % 10000`, loopback only), starts `python -m searx.webapp`, waits for `/healthz`, runs one test query, exports `TALENT_SEARXNG_URL`. Its log is copied to `penny_results/<job>/searxng.log`. |
| `searxng_settings.yml` | Instance settings; engines are SearXNG's defaults (DuckDuckGo, Brave, Startpage, Qwant, Mojeek, Wikipedia) plus Bing. Google stays off (CAPTCHAs from datacenter IPs). |
| `src/talent/sources/websearch.py` | Provider chain `searxng` → `google` → `brave` (`websearch.providers` in `config/sources.yaml`). Query templates with `{name} {short} {ticker} {exchange} {domain} {person}`. Results are cached on disk like every other HTTP response (`websearch.cache_days`). Denylisted hosts (LinkedIn, Crunchbase, ...) are never fetched; their URLs are pointers only. |
| enrich part `web` (`stages/enrich.py`) | Per company: (1) parse "Name - Title - Company" result titles into mentions; (2) run the LLM extractor over all titles+snippets as one short document; (3) fetch up to `max_pages` result pages that look like leadership pages or appointment news (polite client: robots, cache, denylist) and extract people from them (source kind `web_page`). |
| `stages/filings.py` (India) | When the company site exposes fewer than two annual-report PDFs, `find_annual_report_pdfs` searches for them (`"<short name>" "annual report" filetype:pdf`) and feeds them to the same PDF extraction. |
| `stages/profiles.py` (new stage, after `resolve`) | **Profile matching.** For each resolved person (most senior first, `max_people_for_profiles`), searches `"<person>" "<company>"`, scores each result 0-1 on name-in-title, company-in-snippet, profile host, current-title words, and stores the top links as `Person.profile_links`, adds a `profile_url` claim per strong match (≥ 0.75), bumps confidence, and upgrades `cannot_verify` to `probably_genuine` when two strong matches exist. Exported per person as `profiles` in `dashboard.json`. |
| CLI | `talent search "query"` (ad-hoc query through the provider chain), `talent search-check` (health + sample people query + one profile match). `run-all` stages are now `fetch,enrich,resolve,profiles,score`; enrich parts `site,news,research,web`. |
| Tests | `tests/test_websearch.py` (offline, SearXNG mocked) runs inside every pilot job. |

Where search is used, in one line: **people** (who is at the company: snippets, pages, news),
**documents** (annual reports the site hides), **profiles** (which public page is about this
person at this company). Anything else that needs "look it up on the web" should go through
`websearch.search()` so caching, provider fallback and the denylist apply.

Validation so far (30 Oct 2026, CPU-only jobs with `PENNY_LLM=0`, ihub partition, account d4):

| Job | Result |
|---|---|
| 48600 | SearXNG up on the node (48 results from Bing/Brave/DuckDuckGo), search-check ok, 6/6 tests, 4 companies, 0 errors, 10 pages fetched, 14 profile claims. Title parser let company names through ("Key Management", "Our Leadership"). |
| 48659 | Stricter parser, but 0 search people: the cache was keyed on the per-job SearXNG port, so every query re-ran against engines already throttling the node (DuckDuckGo timeouts, Google 429). |
| 48683 | Cache keyed by query, 1 query / 2 s: 13 people from search for AXITA (1), GENNEX (6), IPDN (9), e.g. Kushal Patel (MD, Axita), Arihant Baid (MD, Gennex), Jodi Shamblott (IPDN); 11 `web_page` docs; 15 profile claims; 6/6 tests. |

Known limits: snippet people include some past or peripheral staff (a CFO now at another company whose profile still
mentions Gennex); they land as low-authority `named_staff` mentions and the extractor/profile stages decide what sticks.
DuckDuckGo times out from the cluster; Bing and Brave carry most answers. The full pilot with the LLM over snippets and
pages (job 48598, GPU) is queued until an ihub GPU frees up.

## 4. How to run

Submit from the login node. Accounts: `plafnet` (partition u22, 80-CPU group cap, often full), `plafnet2`
(gnode113-118, GPU minutes exhausted until about 1 Nov 2026), and `d4` (partition **ihub**, 12 nodes,
204 CPU / 17 GPU group cap, 4-day wall), which is what the SearXNG pilot used:
`sbatch -A d4 -p ihub --qos=d4 --gres=gpu:1 -n 10 ...`. On plafnet:

```bash
# full 100-company run (about 7.5 h on a 1080 Ti / 2080 Ti)
PENNY_MODE=full sbatch -A plafnet -p u22 --qos=normal --nodelist= --exclude=gnode033 --gres=gpu:1 -n 10 --time=1-00:00:00 penny_run.sh
```

```bash
# rerun some companies on top of the latest database, then refresh export + overviews for all 100
PENNY_MODE=rerun PENNY_TICKERS="india:A1L GPRO" PENNY_RESTORE_DB=penny_results/47991/talent.db PENNY_OLLAMA_TIMEOUT=180 PENNY_CHUNK_CHARS=15000 sbatch -A plafnet -p u22 --qos=normal --nodelist= --exclude=gnode033 --gres=gpu:1 -n 10 --time=6:00:00 penny_run.sh
```

Watch a job: `squeue -u nishanth.r`, `tail -f logs/penny_<job>.log` (filter noise with
`grep -vE '\[\?25|pulling [0-9a-f]{12}|ydantic'`). You can `ssh gnodeNNN` only while your job
runs there. Results appear in `penny_results/<job>/` only when the job ends.

Rebuild and publish the site after a run:

```bash
python3 build_site.py penny_results/<job> && git add docs && git commit -m "site: job <job>" && git push
```

## 5. What was done, in order (28-30 Oct 2026)

1. Git access from the login node via a PAT in `~/.git-credentials` (first token was pasted
   in chat, so it was revoked and rotated; never print it). Commit identity Nishanth-nishu.
2. Ollama staged to node scratch (`ollama_env.sh`, `ollama_node.sh`, `OLLAMA.md`), verified on
   gnode114 with llama3.2:3b. Binary downloads must run from the login node, not a compute node.
3. Private pipeline repo cloned; `penny_run.sh` written; pilot runs on 2 tickers found and fixed
   the SQLite lock and employee_count bugs (branch `ada-fixes`).
4. Overview summariser added (`summarize_overviews.py`), prompt tuned twice so the model reads
   score bands, coverage and the integrity penalty correctly.
5. Full run, job 46482 on gnode027 (GTX 1080 Ti), 7 h 20 min: 77 scored, 23 skipped
   (14 Ollama 900 s timeouts, 7 parser bug, 2 DNS). `PENNY_RESULTS.md` written. While it ran,
   `penny_live_scores.py` and `penny_db_snapshot.sh` were added because copying a WAL-mode
   SQLite file shows a stale checkpoint.
6. Website: `build_site.py` and `docs/` (commit 8031c18).
7. Rerun job 47116 on gnode033 failed completely: that node ran Ollama at CPU speed
   (31 prompt tokens/s vs 329-724 on a working GPU). `penny_run.sh` now checks `ollama ps`
   for `100% GPU` after llm-check and exits 3 otherwise, logs the driver version, and keeps
   the Ollama serve log in the results dir.
8. Rerun job 47396 on gnode057 (RTX 2080 Ti) with a 300 s timeout: 12 of 23 recovered,
   89 of 100 scored. Site rebuilt from it (commit f4a7ebc).
9. `PENNY_CHUNK_CHARS` added, `PENNY_RESTORE_DB` now always replaces the scratch DB;
   job 47991 submitted for the last 11 companies with 15000-char chunks.
10. Job 47991 (gnode049, 55 min) recovered AMOD, JZ and ALEC: 92 of 100 scored. The other 8
   time out on their first chunk regardless of size; the model loops inside the JSON-schema
   output because nothing caps `num_predict`. Site rebuilt from 47991.

## 6. Cluster lessons (read before running anything)

- Ollama on a node can silently run on CPU. Healthy numbers: llm-check probe (527 tokens)
  under 4 s; a 10k-token chunk in 20-35 s. If the first calls are 10x slower, kill the job
  and resubmit elsewhere. gnode033 did this; the guard in `penny_run.sh` now catches it.
- Do not pin `--nodelist` to a busy node; SLURM queued such a job for 2.5 days. Letting it
  choose (with `--exclude=gnode033`) started within seconds.
- u22 cards are 11 GB, so `ollama_num_ctx` is forced to 16384 (the repo default 32768 does
  not fit). A 24 GB card (plafnet2 gnode114 has an RTX 3090) could use 32768 or a bigger model.
- `talent.db` is WAL mode: never `cp` it while a job runs; use the backup API
  (`penny_live_scores.py`). Remove stale `-wal`/`-shm` files before restoring a DB.
- Python 3.12 on nodes: `/software/apps/u22/python/3.12.15/bin/python3.12` needs
  `LD_LIBRARY_PATH=/software/apps/u22/python/3.12.15/lib`.
- Log timestamps inside a job are IST (node clock); the script's own stage headers are UTC.
- `scontrol update TimeLimit` on a running job is denied; size `--time` generously.
- The 8B model loops on some 40k-char chunks until any timeout; smaller chunks are the
  remedy being tested in job 47991.

## 7. Open items and work that can run in parallel

These do not depend on each other; each can be its own session or person.

- **Finish the last 8 companies**: add `"num_predict": 4096` to the Ollama `options` dict in
  `src/talent/extract/bios.py` (branch `ada-fixes`) so runaway chunks stop instead of timing out,
  then rerun A1L GATECH GPRO IPDN TENX XHG XPON DFDV from `penny_results/47991/talent.db`.
  Alternatives: llama3.2:3b, or a 24 GB plafnet2 node after 1 Nov with a larger model.
- **Score quality**: leadership is <=10 and technical bench 0 almost everywhere, so the
  ranking is really a momentum ranking. Worth checking what the extraction returns for a
  few companies (`talent people show <ticker>`, `talent score <ticker> --explain` inside a
  job) and whether a bigger model changes that.
- **Upstream the fixes**: branch `ada-fixes` in the private clone has three commits the
  author (TomatoChocolate12) does not have; open a PR or send a patch.
- **Site polish**: `build_site.py` is a single file with inline CSS; adding per-company
  pages, sector filters or score histograms is self-contained work.
- **Compare runs**: `penny_results/46482` vs `47396` share a DB lineage; the pipeline's
  `signals` table records score diffs between runs and is not surfaced anywhere yet.

## 8. Conventions for Claude sessions working here

- Heavy work runs in `/scratch/nishanth.r` on compute nodes; this folder holds scripts,
  notes and small results, and every change is pushed to `penyc_sm_dashboard` `main`.
- Times are reported in UTC and IST.
- Never print the contents of `~/.git-credentials`.
- Commits end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Foreground `sleep` is blocked for Claude; use background watcher loops for jobs.
- Memory notes for Claude live outside the repo in
  `~/.claude/projects/-home2-nishanth-r-pen-sm/memory/` (penny-pipeline-on-ada.md,
  ollama-on-ada.md, ada-cluster-workflow.md, penyc_sm_dashboard-repo.md).
