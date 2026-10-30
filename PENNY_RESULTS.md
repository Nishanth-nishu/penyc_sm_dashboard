# Penny-stocks talent pipeline: results

Current state (after rerun job 47991, 30 Oct 2026): **92 of 100 companies scored**, 65 with named people, 8 still skipped by Ollama timeouts (A1L, GATECH, GPRO, IPDN, TENX, XHG, XPON, DFDV). The website and `docs/` are built from `penny_results/47991/`, which holds the complete export.

## Full run (job 46482)

Job 46482, gnode027 (GTX 1080 Ti 11 GB), account plafnet / partition u22, model llama3.1:8b via local Ollama.
Started 2026-10-29 09:15 UTC (14:45 IST), finished 16:35 UTC (22:05 IST), 7 h 20 min, exit 0.

Outputs in `penny_results/46482/`:

- `export/scores.csv` – 100 companies ranked (score, coverage, components, flags)
- `overviews.md` / `overviews.json` – one plain-prose overview per company, written by `summarize_overviews.py`
- `dashboard.html`, `export/dashboard.json`, `export/universe.csv`
- `talent.db` (ignored by git, on the cluster only); `live/` holds the 10-minute snapshots taken while the job ran

## Website

The results are published at **https://penycsmdashboard.vercel.app/** (Vercel, deployed from `docs/`, which
`build_site.py` writes: summary and leaderboard, interactive dashboard, all company overviews with a text
filter, scores.csv). Rebuild after a new run with

```bash
python3 build_site.py penny_results/<jobid> && git add docs && git commit -m "site: job <jobid>" && git push
```

Vercel redeploys the site about a minute after the push.

## Headline numbers

| | |
|---|---|
| Companies processed | 100 (50 India, 50 US) |
| Companies with at least one named person | 50 (93 after reruns and the web-search pass) |
| Companies with no people (no filing text found, or stage failed) | 50 (31 India, 19 US); 7 after reruns and web search: AGOL, CHANDRIMA, ESSENTIA, EXXARO, GROWINGTON, SIKKO, WORTH |
| Score band | 98 "weak" (< 25) and 2 "middling" (25-50) after reruns: Tenax Therapeutics 30.3, GACM Technologies 25.9 |
| Going-concern flags | 24 (35 after reruns) |
| Reverse-merger flags | 9 (12 after reruns) |
| Per-company failures | 23 (0 after reruns, see below) |

Top 10 by talent score:

| Market | Ticker | Name | Score | Coverage | People |
|---|---|---|---|---|---|
| us | TENX | Tenax Therapeutics (added by rerun 48860) | 30.3 | 0.70 | 17 |
| india | GATECH | GACM Technologies (added by rerun 48860) | 25.9 | 0.60 | 17 |
| india | URJA | Urja Global | 23.2 | 0.60 | 33 |
| india | IVC | IL&FS Investment Managers | 21.6 | 0.52 | 10 |
| india | AVROIND | Avro India | 21.5 | 0.21 | 13 |
| india | EVEXIA | Evexia Lifecare | 21.0 | 0.60 | 23 |
| india | LANDSMILL | Landsmill Green | 21.0 | 0.60 | 23 |
| us | DAVI | Davion Healthcare | 21.0 | 0.60 | 8 |
| india | VSL | Viram Suvarn (added by rerun 47396) | 21.0 | 0.45 | 22 |
| india | STARLENT | StarlinePS Enterprises | 20.3 | 0.60 | 16 |

The ranking is driven almost entirely by the momentum component (headcount / hiring / insider data); leadership is 10 or less for nearly every company and technical bench is 0 everywhere, which is what an 8B model extracting from microcap filings produces.

## Failures (23 of 100, company skipped, pipeline continued)

| Cause | Count | Companies |
|---|---|---|
| Ollama call exceeded `ollama_timeout_s` (900 s): the 8B model loops on a long filing chunk | 14 | A1L, GATECH, ASHNI, VSL, GPRO, IPDN, FTFT, BIAF, TENX, XHG, XPON, ALEC, DFDV, AMOD |
| `edgar.employee_count` int('') bug (regex matched a lone comma) | 7 | BKYI, MEDS, VSEE, VSEED, OLB, JZ, SLNH |
| DNS failure on a source fetch (unhandled, aborts the company) | 2 | SOAR, YMAT |

The int('') bug is fixed on the local `ada-fixes` branch of the clone (commit 91e5312). Each timeout costs ~15–25 min; lowering `ollama_timeout_s` to ~180 s (config/sources.yaml) would cap that at 3 min per bad chunk.

## Rerun attempts

**Job 47116 (gnode033, 29 Oct 2026 17:28-20:59 UTC / 22:58-02:29 IST): failed, nothing new scored.**
`PENNY_MODE=rerun` over the 23 skipped companies with `ollama_timeout_s: 180`, DB restored from job 46482.
Ollama ran at CPU speed on that node: 31 prompt tokens/s against 329 tokens/s on gnode027 (same GTX 1080 Ti
class), the llm-check probe took 27 s instead of under 4 s, and staging the venv, Ollama and models took 51 min
instead of seconds. Every one of the 23 companies timed out (one got "connection refused" while the server was
restarting), so `penny_results/47116/export/scores.csv` is identical to 46482's. The one useful output is
`penny_results/47116/overviews.*`: the summaries were regenerated with the corrected prompt and now read a zero
integrity penalty as "no red flags" instead of as a warning.

Fixes in `penny_run.sh` after this: it prints the driver version, dumps `ollama ps` after llm-check and exits 3
unless the model shows `100% GPU` (`PENNY_ALLOW_CPU=1` overrides), and keeps the Ollama server log as
`penny_results/<job>/ollama_serve.log` so a slow node can be diagnosed after the job is gone.

**Job 47392:** pinned to gnode027 (warm scratch) but the scheduler projected a start on 1 Nov, so it was cancelled.

**Job 47396 (gnode057, RTX 2080 Ti, 29 Oct 2026 21:12-22:55 UTC / 30 Oct 02:42-04:25 IST): 12 of 23 recovered, exit 0.**
Same 23 companies with `ollama_timeout_s: 300`, DB restored from job 46482; the GPU guard reported `100% GPU`
and the model averaged 724 prompt tokens/s. Newly scored: VSL 21.0 (22 people), BIAF 17.0, BKYI 16.1, OLB 15.0,
SLNH 13.3, ASHNI 8.9, SOAR 7.0, FTFT 5.9, YMAT 2.0, VSEE 1.3, VSEED 1.3, MEDS 0.0 (27 people). The parser-bug and
DNS companies all came back; of the 14 original timeouts only 3 did (ASHNI, VSL, BIAF).

Still skipped after two attempts, each timing out twice at 300 s on one long filing chunk: A1L, GATECH, GPRO,
IPDN, TENX, XHG, XPON, ALEC, DFDV, AMOD, JZ. A longer timeout will not help (the same chunks ran past 900 s in
job 46482). Options: lower `ollama_chunk_chars` in `config/sources.yaml` (default 40000) so each call is shorter,
or run those 11 with a stronger model on a 24 GB card (plafnet2 nodes, once GPU minutes reset ~1 Nov 2026).

**Job 47991 (gnode049, RTX 2080 Ti, 30 Oct 2026 08:09-09:04 UTC / 13:39-14:34 IST): 3 of 11 recovered, exit 0.**
`ollama_chunk_chars: 15000`, `ollama_timeout_s: 180`, DB restored from job 47396. Newly scored: AMOD 15.8 (30 people,
rank 17), JZ 9.9, ALEC 3.9. Successful calls averaged 4 s (max 21 s), so the chunk size is not the problem for the
other 8: A1L, GATECH, GPRO, IPDN, TENX, XHG, XPON, DFDV each timed out twice on their first chunk. The pipeline sends
Ollama a JSON schema (`format`) at temperature 0 with no `num_predict` cap, so on those documents the model emits
list entries forever until the client gives up. The fix is in the pipeline, not the job: add `num_predict` (about 4096)
to the Ollama `options` in `src/talent/extract/bios.py` so a runaway chunk returns truncated JSON, fails validation and
is logged as a bad chunk while the company's other chunks still count.

**Job 48598 (gnode095, RTX 3080 Ti, 30 Oct 2026 16:00-16:23 UTC / 21:30-21:53 IST): GPU pilot of the search layer, exit 0.**
AXITA, GENNEX, IPDN, URJA with Ollama, SearXNG, `num_predict` cap, 300 s timeout, 15000-char chunks. The plumbing worked
(GPU guard, search-check, 6/6 tests, 2 `web_page` docs for URJA) but AXITA and GENNEX got no people: from the node Bing
ignored the query and returned trending pages, Brave was rate-limited and DuckDuckGo CAPTCHA'd, so the 60 "results" were
junk. Fixed afterwards in the client (`relevant()` filter, no caching of empty answers) and in the engine set (README 3a).

**Job 48860 (gnode095, RTX 3080 Ti, 30 Oct 2026 16:22-18:04 UTC / 21:52-23:34 IST): 11 of 35 gained people, exit 0.**
`PENNY_MODE=rerun` over the 35 companies with no named people (the 8 loopers among them), DB restored from job 47991,
`num_predict: 4096`, `ollama_timeout_s: 300`, `ollama_chunk_chars: 15000`, SearXNG on. 158 Ollama calls, 0 timeouts,
11 outputs truncated by the cap and dropped as invalid JSON (one chunk each for A1L, DISHTV, GATECH, DFDV, GPRO, TENX)
while the companies' other chunks counted. All 8 loopers are scored: TENX 30.3 (17 people), GATECH 25.7 (17),
DFDV 19.2 (28), XPON 14.7 (11), IPDN 13.0 (20), XHG 10.4 (8), A1L 9.5 (24), GPRO 3.1 (16); also AFIL 16.1 (21),
DISHTV 12.2 (31), TUNITEX 8.2 (1). 100 of 100 scored, 76 with named people. Search contributed only 10 mentions:
the job ran the pre-filter client, so its SearXNG instance was restarted mid-run with Bing off and then Yahoo off
(DuckDuckGo + Brave only). The 24 companies still without people are all Indian BSE names whose filings exposed no
management text: AGOL, AVANCE, AXITA, BRIDGESE, BTML, CHANDRIMA, COMFINTE, DAVANGERE, EMPOWER, ESSENTIA, EXXARO,
GANGAFORGE, GENNEX, GROWINGTON, KSHITIJPOL, MISHTANN, NDL, OMEGAIN, SHAH, SIKKO, TITANIN, ULTRACAB, WORTH, ZEEMEDIA.

**Job 49406 (gnode103, CPU only, 30 Oct 2026 18:06-18:53 UTC / 23:36-00:23 IST): 24 of 35 gained people, exit 0.**
Search-only pass (`PENNY_LLM=0 PENNY_STAGES=enrich,resolve,profiles,score PENNY_ENRICH_PARTS=web`, DB restored from
48860) with the fixed client (`relevant()` filter, no caching of empty answers) and the new engine set. Yahoo and Brave
answered, DuckDuckGo timed out or CAPTCHA'd (137 engine errors in `searxng.log`); the filter dropped unrelated results
79 times (e.g. 14 of 38 for Akme Fintrade). 17 of the 24 companies that had nobody now have named people from search
snippets, among them Kushal Patel (MD, Axita Cotton), Arihant Baid (MD, Gennex), Hiralal Tilva (CMD, Ganga Forging),
Mahendra Jain (Chairman, Kshitij Polyline), Anmol Sinha (ED, Titan Intech), Dinesh Garg (CFO, Zee Media), Abhijith
Shamanur (ED, Davangere Sugar), Srikrishna Bhamidipati (Chairperson, Avance). Profile matching recorded 236 `profile_url`
claims on 137 people (87 people carry profile links in the export), including for companies whose people came from
filings (DISHTV 29, AFIL 21, GATECH 20, DFDV 19, IPDN 17). **93 of 100 companies now have named people**; scores moved
only slightly (AVANCE and EMPOWER 7.5 → 17.5, COMFINTE 15.8, GANGAFORGE 11.7, BTML 10.8) because snippet people carry
low authority. Still empty: AGOL, CHANDRIMA, ESSENTIA, EXXARO, GROWINGTON, SIKKO, WORTH. Known noise: when the company
name is a generic word the filter lets namesakes through (Bridge Securities → a Singapore "Capital Bridge Securities";
Empower India → a US "Empower"); those land at confidence 0.4-0.55 as `named_staff`.

`penny_results/49406/` is now the most complete export (100 scored, 93 with people); use its `talent.db` as
`PENNY_RESTORE_DB` for any further rerun. Its `overviews.*` are copied from 48860 (CPU jobs skip the overview step).

## Rerunning companies

Inside a job with the venv and Ollama up (see `penny_run.sh`), the DB in `/scratch/nishanth.r/penny/data/talent.db` is incremental:

```bash
talent run-all --ticker us:BKYI --ticker us:MEDS ...   # fixed parser
talent export
.venv/bin/python /home2/nishanth.r/penyc_sm_dashboard/summarize_overviews.py --db data/talent.db --out <results dir>
```

Scratch is per node and purged after ~7–10 days; `PENNY_RESTORE_DB=penny_results/47991/talent.db` restores the latest state on a fresh node.
