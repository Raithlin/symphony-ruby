# Agent applications

The orchestrator is provider and model agnostic — it runs whatever shell command you configure in `agent.command`. The command receives the ticket prompt and context via environment variables.

## Environment variables

The orchestrator sets these before invoking `agent.command`:

| Variable | Source |
|----------|--------|
| `SYMPHONY_PROVIDER` | `agent.provider` |
| `SYMPHONY_MODEL` | `agent.model` |
| `SYMPHONY_PROMPT_FILE` | Path to rendered `PROMPT.md` |
| `SYMPHONY_WORKSPACE` | Workspace directory |
| `SYMPHONY_TICKET_ID` | Ticket identifier (e.g., `#42`) |
| `SYMPHONY_TICKET_PROJECT_ITEM_ID` | GitHub Projects v2 item ID |
| `SYMPHONY_TICKET_TITLE` | Ticket title |
| `SYMPHONY_TICKET_URL` | Ticket URL |
| `SYMPHONY_TICKET_REPOSITORY` | `owner/repo` |

Plus any key-value pairs in `agent.env`.

## Pi

Pi is a coding agent harness. It reads the prompt file via `-p @file` and uses `--provider`/`--model` for API selection.

```yaml
# DeepSeek (direct)
agent:
  provider: deepseek
  model: deepseek-v4-pro
  command: |
    pi --provider "$SYMPHONY_PROVIDER" --model "$SYMPHONY_MODEL" \
       --session-dir "$SYMPHONY_WORKSPACE/.pi-sessions" \
       -p @"$SYMPHONY_PROMPT_FILE"

# DeepSeek via OpenRouter
agent:
  provider: openrouter
  model: deepseek/deepseek-v4-pro
  command: |
    pi --provider "$SYMPHONY_PROVIDER" --model "$SYMPHONY_MODEL" \
       --session-dir "$SYMPHONY_WORKSPACE/.pi-sessions" \
       -p @"$SYMPHONY_PROMPT_FILE"
```

Pi stores sessions in `$SYMPHONY_WORKSPACE/.pi-sessions` so each ticket has isolated session history. It needs its config at `~/.pi/` and its Node.js runtime (typically managed by mise at `~/.local/share/mise/`).

## Claude Code

Anthropic's CLI agent. Uses `-p @file` to read the prompt and `--model` for model selection.

```yaml
agent:
  provider: anthropic
  model: claude-sonnet-4-5
  command: claude --model "$SYMPHONY_MODEL" -p @"$SYMPHONY_PROMPT_FILE"
```

Requires `~/.claude/` for auth and settings.

## Codex

OpenAI's CLI agent. Reads the prompt from stdin (no `--prompt-file` flag) and uses `-m` for the model.

```yaml
agent:
  provider: openai
  model: gpt-5
  command: codex exec -m "$SYMPHONY_MODEL" < "$SYMPHONY_PROMPT_FILE"
```

Requires `~/.codex/` for auth and configuration.

## opencode

Terminal coding agent. Uses `-m` for model and `-p @file` for the prompt.

```yaml
agent:
  provider: anthropic
  model: claude-sonnet-4-5
  command: opencode -m "$SYMPHONY_MODEL" -p @"$SYMPHONY_PROMPT_FILE"
```

## Custom / local models

Any executable that reads a prompt file works:

```yaml
agent:
  provider: local
  model: qwen3-coder
  command: ./scripts/run-local-agent "$SYMPHONY_PROMPT_FILE" "$SYMPHONY_MODEL"
```

The orchestrator only cares that the command exits with code 0 (success) or non-zero (failure). Stdout/stderr are captured and forwarded to notifications.
