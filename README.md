# Symphony Ruby

Ruby orchestrator that polls **GitHub Projects v2** for ready tickets and launches **configurable agent commands**. Provider and model agnostic: use Pi, Claude Code, Codex, opencode, local models, or any wrapper script.

Based on the workflow shape described by [OpenAI Symphony](https://github.com/openai/symphony) (Elixir): poll a tracker → create a workspace per ticket → render a prompt → launch an agent. Configuration lives in `WORKFLOW.md`.

## How it works

1. Polls a GitHub Projects v2 project for items whose status is ready.
2. Creates a per-ticket workspace, optionally cloning a source repo.
3. Runs an optional `after_create` hook (e.g., `bundle install`).
4. Writes a rendered `PROMPT.md` into the workspace.
5. Claims the ticket (assigns the issue, moves it to In Progress).
6. Runs `agent.command` with ticket/workspace environment variables.
7. Optionally auto-creates a branch and PR if the ticket has a configured label.

## Requirements

- Ruby 3.3+
- GitHub authentication: either `gh auth login` or a `GITHUB_TOKEN`
- GitHub access to the project, its fields, and permission to assign issues

## Run

```bash
cd symphony-ruby
bundle install
bin/symphony-ruby ./WORKFLOW.md --once
```

Discord bot:

```bash
bin/symphony-ruby --bot discord
```

Smoke test without GitHub:

```bash
SYMPHONY_DRY_RUN_TICKET='NN-1|Demo ticket' bin/symphony-ruby ./WORKFLOW.md --once
```

Omit `--once` to poll forever.

### Docker

See [docker/README.md](docker/README.md).

## Configuration

`WORKFLOW.md` has YAML front matter and a Markdown prompt template:

```yaml
---
github:
  owner: NomadNest
  project_number: 7
  token: $GITHUB_TOKEN            # optional — falls back to `gh auth token`
ticket:
  status_field: Status
  ready_status: Ready
  in_progress_status: In Progress
workspace:
  root: ~/source/nomadnest-agent-runs
  clone_from: ~/source/nomadnest   # optional
agent:
  provider: deepseek
  model: deepseek-v4-pro
  command: |
    pi --provider "$SYMPHONY_PROVIDER" --model "$SYMPHONY_MODEL" \
       --session-dir "$SYMPHONY_WORKSPACE/.pi-sessions" \
       -p @"$SYMPHONY_PROMPT_FILE"
  max_concurrent_agents: 2
  pr_label: auto-pr               # optional — auto-create PR
poll_interval: 30
chat:                              # optional
  discord:
    bot_token: $DISCORD_BOT_TOKEN
    channel_id: "1234567890"
---
You are working on {{ ticket.identifier }}.

Title: {{ ticket.title }}
URL: {{ ticket.url }}

{{ ticket.body }}
```

Full reference: [docs/configuration.md](docs/configuration.md). Agent examples: [docs/agents.md](docs/agents.md). Discord bot: [docs/discord-bot.md](docs/discord-bot.md).

## Documentation

- [Configuration reference](docs/configuration.md) — all WORKFLOW.md keys, auth, auto-PR, env vars
- [Agent applications](docs/agents.md) — Pi, Claude Code, Codex, opencode, custom
- [Discord bot](docs/discord-bot.md) — setup, slash commands, notifications
- [Docker](docker/README.md) — build, run, agent mounts

## Development

```bash
rake test
```

## Current scope

- Reads organization-owned and user-owned GitHub Projects v2 items.
- Filters tickets by a single-select/text status field.
- Claims tickets (assigns issue, moves to In Progress).
- Runs commands locally in per-ticket workspaces.
- Optional auto-PR when ticket has configured label.
- Discord bot with slash commands and notification embeds.
- Chat adapter interface for adding new platforms.
