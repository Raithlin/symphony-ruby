# Configuration reference

## WORKFLOW.md

`WORKFLOW.md` uses YAML front matter for configuration plus a Markdown body as a prompt template. Variables in `{{ double.brace }}` syntax are replaced at runtime.

### Full example

```yaml
---
github:
  owner: NomadNest
  owner_type: organization        # "organization" or "user" (default: organization)
  project_number: 7
  token: $GITHUB_TOKEN            # optional — falls back to `gh auth token`

ticket:
  status_field: Status            # project field to read/write status
  ready_status: Ready             # value that means "ready to run"
  in_progress_status: In Progress # value set when claiming a ticket
  needs_clarification_status: Needs clarification # value set when agent asks a human question
  assigned_to_current_user_only: false # only pick tickets assigned to the GitHub token viewer
  terminal_statuses:              # statuses that mean "done"
    - Done
    - Closed
    - Cancelled

workspace:
  root: ~/source/nomadnest-agent-runs
  clone_from: ~/source/nomadnest   # optional — source repo to git clone

hooks:
  after_create: |                  # optional — runs once after workspace is created
    bundle install

agent:
  provider: deepseek
  model: deepseek-v4-pro
  command: |
    pi --provider "$SYMPHONY_PROVIDER" --model "$SYMPHONY_MODEL" \
       --session-dir "$SYMPHONY_WORKSPACE/.pi-sessions" \
       -p @"$SYMPHONY_PROMPT_FILE"
  max_concurrent_agents: 2
  pr_label: auto-pr               # optional — create PR if ticket has this label
  env:                            # optional — extra env vars for agent command
    EXTRA_FLAG: enabled

poll_interval: 30                  # seconds between polls (default: 1)

chat:                              # optional
  discord:
    bot_token: $DISCORD_BOT_TOKEN
    channel_id: "1234567890"
    allowed_role_ids: ["9876543210"]
  telegram:
    bot_token: $TELEGRAM_BOT_TOKEN
    chat_id: "-1001234567890"
    allowed_user_ids: ["123456789"]
---
You are working on {{ ticket.identifier }} for NomadNest.

Title: {{ ticket.title }}
URL: {{ ticket.url }}
Repository: {{ ticket.repository }}

{{ ticket.body }}
```

### Key reference

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `github.owner` | string | Yes | — | GitHub org or user name |
| `github.owner_type` | string | No | `organization` | `organization` or `user` |
| `github.project_number` | integer | Yes | — | GitHub Projects v2 project number |
| `github.token` | string | No | `gh auth token` | GitHub PAT or `$GITHUB_TOKEN` |
| `ticket.status_field` | string | No | `Status` | Project field name for status |
| `ticket.ready_status` | string | No | `Ready` | Value that means "ready to run" |
| `ticket.in_progress_status` | string | No | `In Progress` | Value set when claiming |
| `ticket.needs_clarification_status` | string | No | `Needs clarification` | Value set when the agent requests human input |
| `ticket.assigned_to_current_user_only` | boolean | No | `false` | When true, only pick ready issues/PRs assigned to the current GitHub token viewer |
| `ticket.terminal_statuses` | array | No | `[Done, Closed, Cancelled, Duplicate]` | Statuses treated as done |
| `workspace.root` | string | Yes | — | Directory for per-ticket workspaces |
| `workspace.clone_from` | string | No | — | Git repo to clone into each workspace |
| `hooks.after_create` | string | No | — | Shell command run once per workspace |
| `agent.command` | string | Yes | — | Shell command to invoke the agent |
| `agent.max_concurrent_agents` | integer | No | `2` | Max tickets to run in parallel |
| `agent.model` | string | No | — | Set as `$SYMPHONY_MODEL` |
| `agent.provider` | string | No | — | Set as `$SYMPHONY_PROVIDER` |
| `agent.pr_label` | string | No | — | GitHub label that triggers auto-PR |
| `agent.env` | map | No | — | Extra env vars for the agent command |
| `poll_interval` | integer | No | `1` | Seconds between polls |
| `chat.discord` | map | No | — | Discord bot config |
| `chat.telegram` | map | No | — | Telegram bot config |

### Environment variable expansion

Values that start with `$VAR` (e.g., `$GITHUB_TOKEN`) are resolved from the environment. Substrings like `prefix-$VAR-suffix` are also expanded. If an env var is unset, it resolves to an empty string.

## GitHub authentication

Token lookup order:

1. `github.token` from `WORKFLOW.md`, including env expansion (`$GITHUB_TOKEN`)
2. `gh auth token` from your existing GitHub CLI login

If both are unavailable, GitHub polling fails when the GraphQL request is made.

Required permissions:
- **Classic token:** `repo` scope
- **Fine-grained token:** Contents (read/write), Issues (read/write), Pull requests (read/write), Projects (read)

## Auto branch + PR

When `agent.pr_label` is configured and the ticket has that GitHub label, symphony-ruby runs these steps after the agent finishes:

1. Commits any uncommitted changes in the workspace
2. Creates a branch named `{issue-number}-{slugified-title}` (e.g., `176-location-flagged-as-closed-by-users`)
3. Pushes the branch to origin
4. Opens a PR via `gh pr create`

To opt a ticket into auto-PR, add the label (e.g., `auto-pr`) to the GitHub issue. Tickets without the label still run the agent but skip PR creation.

## Environment variables for agent commands

The orchestrator sets these before running `agent.command`:

| Variable | Value |
|----------|-------|
| `SYMPHONY_PROVIDER` | `agent.provider` |
| `SYMPHONY_MODEL` | `agent.model` |
| `SYMPHONY_PROMPT_FILE` | Path to the rendered `PROMPT.md` |
| `SYMPHONY_CLARIFICATION_FILE` | Path the agent can write questions to when it needs human input |
| `SYMPHONY_WORKSPACE` | Workspace directory path |
| `SYMPHONY_TICKET_ID` | Ticket identifier (e.g., `#42`) |
| `SYMPHONY_TICKET_PROJECT_ITEM_ID` | GitHub Projects v2 item ID |
| `SYMPHONY_TICKET_TITLE` | Ticket title |
| `SYMPHONY_TICKET_URL` | Ticket URL |
| `SYMPHONY_TICKET_REPOSITORY` | Repository (e.g., `owner/repo`) |

Plus anything in `agent.env`.

## Clarification requests

If an agent cannot continue without human input, it can write one or more
questions to `$SYMPHONY_CLARIFICATION_FILE` and then exit. After `agent.command`
returns, symphony-ruby reads that file. If it contains non-blank text,
symphony-ruby:

1. Adds a comment to the issue or PR with the clarification request
2. Moves the project item to `ticket.needs_clarification_status`
3. Stops processing that ticket for the current run and skips auto-PR creation

After a human answers the issue comment, move the project item back to
`ticket.ready_status` so the next polling loop can pick it up again.

## Trace output (`--once`)

Each major step prints a trace line:

```text
[symphony-ruby] Loading workflow: /path/to/WORKFLOW.md
[symphony-ruby] GitHub project: owner=NomadNest owner_type=organization project_number=7
[symphony-ruby] GitHub token source: gh auth token
[symphony-ruby] Ticket filter: Status=Ready
[symphony-ruby] Workspace root: /path/to/workspaces
[symphony-ruby] Agent: provider=deepseek model=deepseek-v4-pro max_concurrent=2
[symphony-ruby] Starting one orchestration pass
[symphony-ruby] Ready tickets found: 1
[symphony-ruby] Preparing #123: Example ticket
[symphony-ruby] Ticket: #123
[symphony-ruby] Workspace name: 123
[symphony-ruby] Workspace: /path/to/workspaces/123
[symphony-ruby] Prompt: /path/to/workspaces/123/PROMPT.md
[symphony-ruby] Launching agent for #123
[symphony-ruby] Finished one orchestration pass
```

If it prints `Ready tickets found: 0`, the GitHub query succeeded but no project item matched the configured status filter.

Workspace directory names are sanitized: `#176` → `176`, so the directory is `/path/to/workspaces/176` not `#176`.
