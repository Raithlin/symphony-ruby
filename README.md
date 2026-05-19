# Symphony Ruby for NomadNest

Ruby Symphony-like orchestrator that uses **GitHub Projects v2** as the ticket source and launches **configurable agent commands**. It is intentionally provider/model agnostic: use Codex, Claude, Gemini, Pi, OpenCode, local models, or any wrapper script as long as it can be invoked from a shell command.

This project is based on the workflow shape described by [OpenAI Symphony](https://github.com/openai/symphony) (Elixir): poll a tracker, create a workspace per ticket, render a workflow prompt, launch an agent, and keep orchestration configuration in `WORKFLOW.md`.

## How it works

1. Polls a GitHub Projects v2 project for items whose configured status is ready.
2. Creates a workspace per project item.
3. Clones the source repo (`workspace.clone_from`) into the workspace if configured.
4. Runs `hooks.after_create` the first time a workspace is created (for one-time setup).
5. Writes a rendered `PROMPT.md` into that workspace.
6. Claims the ticket by assigning the underlying issue/PR to the current GitHub user and moving the project item to `ticket.in_progress_status`.
7. Runs `agent.command` with ticket/workspace/model/provider environment variables.
8. If `agent.pr_label` is configured and the ticket has that label, commits changes, creates a branch, pushes to origin, and opens a PR via `gh pr create`.

## Requirements

- Ruby 3.3+ (tested here with Ruby 4.0.3)
- GitHub authentication through either:
  - an existing GitHub CLI session (`gh auth login` / `gh auth status`), or
  - `GITHUB_TOKEN` / `github.token` in `WORKFLOW.md`
- GitHub access to the project, project fields, project item contents, and permission to assign the underlying issue/PR

You do **not** need to manually create/export a token if `gh auth status` already works. Symphony Ruby will call `gh auth token` automatically when `github.token` is omitted or resolves to an empty value.

## Run

```bash
cd /home/stephen/source/symphony-ruby
bundle install
gh auth status
bin/symphony-ruby ./WORKFLOW.md --once
```

To run as a Discord bot instead:

```bash
bin/symphony-ruby --bot discord
```

If `gh auth status` fails, authenticate first:

```bash
gh auth login
```

Alternatively, provide a token explicitly:

```bash
export GITHUB_TOKEN=ghp_your_token_here
bin/symphony-ruby ./WORKFLOW.md --once
```

For a safe local smoke test that does not call GitHub:

```bash
SYMPHONY_DRY_RUN_TICKET='NN-1|Demo NomadNest ticket' bin/symphony-ruby ./WORKFLOW.md --once
```

Omit `--once` to keep polling forever.

### What `--once` prints

`--once` is intended for console testing. It prints trace lines for each major step, for example:

```text
[symphony-ruby] Loading workflow: /home/stephen/source/symphony-ruby/WORKFLOW.md
[symphony-ruby] GitHub project: owner=Raithlin owner_type=user project_number=1
[symphony-ruby] GitHub token source: gh auth token
[symphony-ruby] Ticket filter: Status=Ready
[symphony-ruby] Workspace root: /home/stephen/source/nomadnest-agent-runs
[symphony-ruby] Agent: provider=deepseek model=deepseek-v4-pro max_concurrent=2
[symphony-ruby] Starting one orchestration pass
[symphony-ruby] Querying GitHub Projects v2 owner=Raithlin owner_type=user project_number=1 cursor=<first>
[symphony-ruby] Project item PVTI_xxx status="Ready" title="Example ticket"
[symphony-ruby] Ready tickets found: 1
[symphony-ruby] Preparing #123: Example ticket
[symphony-ruby] Ticket: #123
[symphony-ruby] Workspace name: 123
[symphony-ruby] Workspace: /home/stephen/source/nomadnest-agent-runs/123
[symphony-ruby] Cloning /home/stephen/source/nomadnest into workspace 123
[symphony-ruby] Prompt: /home/stephen/source/nomadnest-agent-runs/123/PROMPT.md
[symphony-ruby] Assigning #123 to raithlin
[symphony-ruby] Moving #123 to Status=In Progress
[symphony-ruby] Launching agent for #123
[symphony-ruby] pi --provider "$SYMPHONY_PROVIDER" --model "$SYMPHONY_MODEL" ...
[symphony-ruby] Finished one orchestration pass
```

If it prints `Ready tickets found: 0`, the GitHub query worked but no project item matched the configured `ticket.status_field` and `ticket.ready_status`.

Workspace directory names are sanitized for filesystem safety. For example, GitHub issue `#176` becomes workspace name `176`, so the directory is:

```bash
/home/stephen/source/nomadnest-agent-runs/176
```

not `#176`.

## Configuration

`WORKFLOW.md` has YAML front matter plus a Markdown prompt template. Example:

```yaml
---
github:
  owner: NomadNest
  owner_type: organization
  project_number: 7
  # Optional. If omitted or empty, Symphony Ruby falls back to `gh auth token`.
  token: $GITHUB_TOKEN
ticket:
  status_field: Status
  ready_status: Ready
  in_progress_status: In Progress
  terminal_statuses: [Done, Closed, Cancelled]
workspace:
  root: ~/source/nomadnest-agent-runs
  # Optional: source repo to clone into each workspace
  clone_from: ~/source/nomadnest
hooks:
  # Optional: runs after workspace is created & cloned
  # after_create: |
  #   bundle install
agent:
  provider: deepseek
  model: deepseek-v4-pro
  command: |
    pi --provider "$SYMPHONY_PROVIDER" --model "$SYMPHONY_MODEL" --session-dir "$SYMPHONY_WORKSPACE/.pi-sessions" -p @"$SYMPHONY_PROMPT_FILE"
  max_concurrent_agents: 2
  # Optional: if ticket has this label, create branch + PR after agent finishes
  pr_label: auto-pr
  env:
    EXTRA_FLAG: enabled
poll_interval: 30
chat:
  # Optional: Discord bot and/or Telegram notifications
  discord:
    bot_token: $DISCORD_BOT_TOKEN
    channel_id: "1234567890"
    # Optional: restrict slash commands to these role IDs
    allowed_role_ids: ["9876543210"]
  telegram:
    bot_token: $TELEGRAM_BOT_TOKEN
    chat_id: "-1001234567890"
---
You are working on {{ ticket.identifier }} for NomadNest.

Title: {{ ticket.title }}
URL: {{ ticket.url }}
Repository: {{ ticket.repository }}

{{ ticket.body }}
```

### Auto branch + PR (optional)

When `agent.pr_label` is set to a label name (e.g., `auto-pr`), symphony-ruby checks the ticket's labels after the agent command finishes. If the label is present, it:

1. Commits any uncommitted changes in the workspace
2. Creates a branch named `{issue}-{slugified-title}` (e.g., `176-location-flagged-as-closed-by-users`)
3. Pushes the branch to origin
4. Opens a PR via `gh pr create` (uses the repo's PR template if one exists)

To opt a ticket into auto-PR, add the label to the GitHub issue/PR. Without the label, symphony-ruby runs the agent but does not open a PR.

### Provider/model agnostic commands

The orchestrator does not know about model APIs. It passes these variables to any command:

- `SYMPHONY_PROVIDER`
- `SYMPHONY_MODEL`
- `SYMPHONY_PROMPT_FILE`
- `SYMPHONY_WORKSPACE`
- `SYMPHONY_TICKET_ID`
- `SYMPHONY_TICKET_PROJECT_ITEM_ID`
- `SYMPHONY_TICKET_TITLE`
- `SYMPHONY_TICKET_URL`
- `SYMPHONY_TICKET_REPOSITORY`

### Supported agent applications

Symphony Ruby works with any CLI agent that reads a prompt file and respects `$SYMPHONY_*` environment variables. Below are examples for common coding agents.

**Pi** (coding agent harness):

```yaml
# DeepSeek (direct)
agent:
  provider: deepseek
  model: deepseek-v4-pro
  command: |
    pi --provider "$SYMPHONY_PROVIDER" --model "$SYMPHONY_MODEL" --session-dir "$SYMPHONY_WORKSPACE/.pi-sessions" -p @"$SYMPHONY_PROMPT_FILE"

# DeepSeek via OpenRouter
agent:
  provider: openrouter
  model: deepseek/deepseek-v4-pro
  command: |
    pi --provider "$SYMPHONY_PROVIDER" --model "$SYMPHONY_MODEL" --session-dir "$SYMPHONY_WORKSPACE/.pi-sessions" -p @"$SYMPHONY_PROMPT_FILE"
```

**Claude Code** (Anthropic's CLI agent):

```yaml
agent:
  provider: anthropic
  model: claude-sonnet-4-5
  command: claude --model "$SYMPHONY_MODEL" -p @"$SYMPHONY_PROMPT_FILE"
```

**Codex** (OpenAI's CLI agent):

```yaml
agent:
  provider: openai
  model: gpt-5
  command: codex exec -m "$SYMPHONY_MODEL" < "$SYMPHONY_PROMPT_FILE"
```

**opencode** (terminal coding agent):

```yaml
agent:
  provider: anthropic
  model: claude-sonnet-4-5
  command: opencode -m "$SYMPHONY_MODEL" -p @"$SYMPHONY_PROMPT_FILE"
```

**Custom / local models:**

```yaml
agent:
  provider: local
  model: qwen3-coder
  command: ./scripts/run-local-agent "$SYMPHONY_PROMPT_FILE" "$SYMPHONY_MODEL"
```

## GitHub authentication details

Token lookup order is:

1. `github.token` from `WORKFLOW.md`, including env expansion such as `$GITHUB_TOKEN`
2. `gh auth token` from your existing GitHub CLI login

So if `gh auth status` already works, you can omit `github.token` entirely or leave `GITHUB_TOKEN` unset.

```bash
gh auth status
bin/symphony-ruby ./WORKFLOW.md --once
```

If both `github.token`/`GITHUB_TOKEN` and `gh auth token` are unavailable, live GitHub polling will fail when the GraphQL request is made.

## Development

```bash
rake test
```

### Discord bot (optional)

Symphony Ruby can run as a Discord bot, accepting slash commands and posting notifications to a configured channel.

**Setup:**

1. Create a Discord application + bot at https://discord.com/developers/applications
2. Go to **Bot** → **Reset Token** and copy the token
3. Enable **Developer Mode** in Discord, right-click your target channel → **Copy ID**
4. (Optional) Copy role IDs the same way if you want to restrict commands
5. Invite the bot to your server with scopes `bot` + `applications.commands` and permissions `Send Messages`, `Embed Links`, `Use Slash Commands`

**Configuration:**

```yaml
chat:
  discord:
    bot_token: $DISCORD_BOT_TOKEN
    channel_id: "1234567890"
    allowed_role_ids: ["9876543210"]  # optional
```

**Running:**

```bash
export DISCORD_BOT_TOKEN=your_token_here
bin/symphony-ruby --bot discord
```

The bot runs persistently, listening for commands and sending notifications to the configured channel.

**Slash commands:**
| Command | What it does |
|---------|-------------|
| `/symphony run` | Polls GitHub for ready tickets and runs the orchestrator |
| `/symphony status` | Shows current owner, project, provider/model, channel |
| `/symphony review` | Lists open PRs matching the configured `pr_label` |

If `allowed_role_ids` is configured, only users with at least one matching role can use these commands.

**Notifications:**
| Event | Discord message |
|-------|----------------|
| Ticket claimed | Rich embed with 🎫 title, repo, status |
| Agent started | "🚀 Agent started for #42: Title" |
| Agent finished | ✅ Green embed or ❌ Red embed with output |
| PR created | "🔀 PR for #42: url" |
| Error | ⚠️ Yellow embed with error message |
| No ready tickets | "💤 No ready tickets found" |

### Telegram (optional, coming next)

Telegram bot support uses the same `ChatAdapter` interface. Configure it with a bot token and chat ID:

```yaml
chat:
  telegram:
    bot_token: $TELEGRAM_BOT_TOKEN
    chat_id: "-1001234567890"
    allowed_user_ids: ["123456789"]  # optional
```

**Coming next:** `TelegramBot` adapter implementing the same command + notification model as Discord.

## Current scope

- Reads organization-owned and user-owned GitHub Projects v2 items.
- Filters tickets by a single-select/text `Status` field.
- Claims tickets by assigning the underlying issue/PR to the current GitHub user and setting the project item `Status` single-select option to `In Progress`.
- Runs commands locally in per-ticket workspaces.
- Optional: when `agent.pr_label` is configured and the ticket has that label, commits, creates a branch, pushes, and opens a PR via `gh pr create`.
- Draft issues without an assignable content id are still moved to `In Progress`, but assignment is skipped.
- Discord bot with slash commands (`/symphony run`, `/symphony status`, `/symphony review`) and notification embeds.
- Chat adapter interface for adding new platforms (Telegram, Slack, etc.).

