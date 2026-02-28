#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: ./launch.sh [MODEL]"
    echo ""
    echo "  ./launch.sh                        # auto-detects model's max context"
    echo "  ./launch.sh qwen3:1.7b             # explicit model"
    echo "  CTX_LIMIT=8192 ./launch.sh         # override context window"
    exit 0
fi

MODEL="${1:-qwen3:1.7b}"
CUSTOM_MODEL="$(echo "$MODEL" | tr ':/' '-')-max"
MODELFILE="$(mktemp)"

cleanup() {
    rm -f "$MODELFILE"
}
trap cleanup EXIT

if [[ -n "${CTX_LIMIT:-}" ]]; then
    MAX_CTX="$CTX_LIMIT"
    echo "Using user-specified context: $MAX_CTX"
else
    MAX_CTX="$(ollama show "$MODEL" 2>/dev/null | awk '/context length/ { print $NF }')"
    MAX_CTX="${MAX_CTX:-32768}"
    echo "Detected max context: $MAX_CTX"
fi

cat > "$MODELFILE" <<EOF
FROM $MODEL
PARAMETER num_ctx $MAX_CTX
EOF

check_load() {
    echo "Loading model to check processor allocation..."
    curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$CUSTOM_MODEL\", \"prompt\": \"\", \"stream\": false, \"keep_alive\": \"5m\"}" \
        > /dev/null &
    local pid=$!

    local ps_output found=0
    for i in $(seq 1 60); do
        ps_output="$(ollama ps 2>/dev/null)"
        if echo "$ps_output" | grep "$CUSTOM_MODEL" | grep -qv "Stopping"; then
            found=1
            break
        fi
        sleep 1
    done
    kill "$pid" 2>/dev/null || true

    if [[ $found -eq 1 ]]; then
        local proc_line
        proc_line="$(echo "$ps_output" | grep "$CUSTOM_MODEL" | grep -v "Stopping")"
        echo "$ps_output"
        if echo "$proc_line" | grep -q "100% GPU"; then
            echo "Processor: 100% GPU"
        elif echo "$proc_line" | grep -qE "100%.*CPU"; then
            echo "Processor: 100% CPU"
        elif echo "$proc_line" | grep -q "CPU/GPU"; then
            echo "Processor: $(echo "$proc_line" | grep -oE '[0-9]+%/[0-9]+% CPU/GPU')"
        fi
    else
        echo "WARNING: Could not verify model load within 60s."
    fi
}

echo "Building model '$CUSTOM_MODEL' from '$MODEL'..."
ollama create "$CUSTOM_MODEL" -f "$MODELFILE"

check_load

echo "Launching Claude with model '$CUSTOM_MODEL'..."
unset CLAUDECODE
ollama launch claude --model "$CUSTOM_MODEL"
