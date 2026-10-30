# Ollama on Ada (any plafnet2 GPU node)

Persistent copy in `/home2/nishanth.r/ollama_persist/`:
- `ollama-v0.40.12.tar.zst` — release archive (login node has no zstd; compute nodes extract it)
- `models/` — Ollama model store, synced back from scratch at the end of every job

Each job stages into node-local `/scratch/nishanth.r/ollama` (extract binary, rsync models),
starts `ollama serve` on a per-job loopback port, pulls the model if missing, and on exit
rsyncs new models back to `/home2`.

## Commands (from the login node)

```bash
# one-shot prompt, exits when done (first run of a model pulls it, ~2 GB for llama3.2:3b)
OLLAMA_MODEL=llama3.2:3b sbatch ollama_node.sh ollama run llama3.2:3b "Say hello"

# run a script that talks to http://$OLLAMA_HOST (ollama_env.sh exports it)
OLLAMA_MODEL=qwen2.5:7b sbatch ollama_node.sh python my_infer.py

# hold a node for interactive use, then ssh to it (see log for the exact export line)
sbatch ollama_node.sh
tail -f logs/ollama_<jobid>.log

# inside an srun shell instead of sbatch
srun --pty -A plafnet2 -p plafnet2 --gres=gpu:1 -c 10 --mem-per-cpu=3G bash -l
source /home2/nishanth.r/penyc_sm_dashboard/ollama_env.sh llama3.2:3b
ollama run llama3.2:3b
ollama_sync_back   # before leaving, to persist pulled models
```

Verified 28 Oct 2026: job 45280 on gnode114 (RTX 3090, 24 GB), 2 min 57 s including the
first pull of llama3.2:3b, answered "Hello, I'm Ada."
