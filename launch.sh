#!/usr/bin/env bash
set -euo pipefail

MODEL="${1:-qwen3:1.7b}"
CUSTOM_MODEL="$(echo "$MODEL" | tr ':/' '-')-max"
MODELFILE="$(mktemp)"

cleanup() {
    rm -f "$MODELFILE"
}
trap cleanup EXIT

cat > "$MODELFILE" <<EOF
FROM $MODEL
PARAMETER num_ctx 32768
EOF

check_vram() {
    echo "Checking VRAM usage..."
    local vram_before
    vram_before="$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')"

    # Load model via REST API with keep_alive so it stays resident
    curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$CUSTOM_MODEL\", \"prompt\": \"hi\", \"stream\": false, \"keep_alive\": \"5m\"}" \
        > /dev/null &
    local pid=$!

    # Poll ollama ps until model appears (up to 60s)
    local ps_output found=0
    for i in $(seq 1 60); do
        ps_output="$(ollama ps 2>/dev/null)"
        if echo "$ps_output" | grep -q "$CUSTOM_MODEL"; then
            found=1
            break
        fi
        sleep 1
    done

    kill "$pid" 2>/dev/null || true

    local vram_after
    vram_after="$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')"

    if [[ $found -eq 1 ]]; then
        echo "$ps_output"
        # Extract PROCESSOR field from the model line
        local proc_line
        proc_line="$(echo "$ps_output" | grep "$CUSTOM_MODEL")"
        if echo "$proc_line" | grep -q "100% GPU"; then
            echo "Model is fully loaded in VRAM."
        elif echo "$proc_line" | grep -q "CPU/GPU"; then
            # Format: "39%/61% CPU/GPU" — GPU% is the second number
            local gpu_pct
            gpu_pct="$(echo "$proc_line" | grep -oE '[0-9]+%/[0-9]+%' | cut -d'/' -f2 | tr -d '%')"
            echo "Model is ${gpu_pct}% in VRAM (split load — not enough VRAM for full model + context)."
        else
            echo "WARNING: Model is NOT in VRAM. Check available GPU memory."
        fi
    else
        local delta=$(( vram_after - vram_before ))
        if [[ $delta -gt 500 ]]; then
            echo "Model appears loaded in VRAM (VRAM increased by ${delta} MiB), but 'ollama ps' missed it."
        else
            echo "WARNING: Could not verify model load — 'ollama ps' shows no model and VRAM delta is only ${delta} MiB."
        fi
    fi

    nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv,noheader,nounits 2>/dev/null \
        | awk -F',' '{printf "GPU VRAM — Used: %s MiB | Free: %s MiB | Total: %s MiB\n", $1, $2, $3}'
}

echo "Building model '$CUSTOM_MODEL' from '$MODEL'..."
ollama create "$CUSTOM_MODEL" -f "$MODELFILE"

check_vram

echo "Launching Claude with model '$CUSTOM_MODEL'..."
unset CLAUDECODE
ollama launch claude --model "$CUSTOM_MODEL"
