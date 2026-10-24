#!/usr/bin/env bash
# ForgeLM Model Server Runner
set -euo pipefail

MODEL_PATH="${1:-/run/media/den/Новый том/60-69 ML Artifacts/phi-4mini/Phi-4-Mini-3.8B-Q4_K_L-Tao-Integrated.gguf}"
PORT="${2:-8080}"
CTX="${3:-8192}"

export LD_LIBRARY_PATH="/home/den/.local/lib/ollama:${LD_LIBRARY_PATH:-}"

echo "=== [ForgeLM / AxiomLLM] Starting High-Performance Model Server ==="
echo "Model: $MODEL_PATH"
echo "Port:  $PORT"
echo "Ctx:   $CTX"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STANDALONE="$SCRIPT_DIR/bin/forgelm_standalone"

# Validate model with pure ASM standalone validator
if [ -x "$STANDALONE" ]; then
    echo "[ForgeLM] Validating model with pure ASM engine..."
    "$STANDALONE" "$MODEL_PATH" || true
fi

exec /home/den/.local/lib/ollama/llama-server \
    -m "$MODEL_PATH" \
    --host 127.0.0.1 \
    --port "$PORT" \
    -c "$CTX" \
    --n-gpu-layers 99 \
    --jinja
