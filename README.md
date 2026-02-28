# claude-local-ollama

Launch [Claude Code](https://claude.ai/claude-code) locally using [Ollama](https://ollama.com) as the model provider.

## Requirements

- [Ollama](https://ollama.com) running locally
- [Claude Code](https://claude.ai/claude-code) installed (`npm install -g @anthropic-ai/claude-code`)
- A model pulled in Ollama (e.g. `ollama pull qwen3:1.7b`)

## Usage

```bash
# Auto-detects the model's max context window
./launch.sh

# Explicit model
./launch.sh qwen3:1.7b

# Override context window
CTX_LIMIT=8192 ./launch.sh qwen3:1.7b
```

## What it does

1. Detects the model's maximum context length via `ollama show`
2. Creates a custom Ollama model with that context configured
3. Reports how the model was loaded (GPU %, CPU %)
4. Launches Claude Code pointed at the local Ollama endpoint
