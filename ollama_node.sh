#!/bin/bash
#SBATCH -A plafnet2
#SBATCH -p plafnet2
#SBATCH -J ollama_infer
#SBATCH -n 10
#SBATCH --gres=gpu:1
#SBATCH --mem-per-cpu=3G
#SBATCH --time=1-00:00:00
#SBATCH --output=/home2/nishanth.r/penyc_sm_dashboard/logs/ollama_%j.log
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=nishanth0962333@gmail.com
#
# No --nodelist on purpose: SLURM picks ANY free plafnet2 GPU node, so the job
# starts as soon as one GPU is free instead of pending on a busy gnode118.
# To force a node:  sbatch --nodelist=gnode118 ollama_node.sh
#
# Usage:
#   sbatch ollama_node.sh                       # hold a node, ollama ready for ssh use
#   sbatch ollama_node.sh python infer.py       # run a command against ollama, then exit
#   OLLAMA_MODEL=qwen2.5:7b sbatch ollama_node.sh python infer.py
#
# Inside the command, talk to the server at http://$OLLAMA_HOST (set by ollama_env.sh).

echo "=========================================="
echo "OLLAMA | job $SLURM_JOB_ID on $SLURM_NODELIST | $(date -u) UTC / $(TZ=Asia/Kolkata date +%H:%M) IST"
echo "=========================================="
nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader

source /home2/nishanth.r/penyc_sm_dashboard/ollama_env.sh "$OLLAMA_MODEL" || exit 1
trap ollama_sync_back EXIT

if [ $# -gt 0 ]; then
    echo "[ollama_node] running: $*"
    "$@"
else
    echo "[ollama_node] holding node. From the login node:"
    echo "    ssh $SLURM_NODELIST"
    echo "    export OLLAMA_HOST=$OLLAMA_HOST PATH=/scratch/nishanth.r/ollama/bin:\$PATH OLLAMA_MODELS=/scratch/nishanth.r/ollama/models"
    echo "    ollama run $MODEL"
    sleep infinity
fi
