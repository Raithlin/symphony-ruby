---
github:
  owner: Raithlin
  owner_type: user
  project_number: 1
  # Optional: omit this if `gh auth token` works in your shell.
  # token: $GITHUB_TOKEN
ticket:
  status_field: Status
  ready_status: Ready
  in_progress_status: In Progress
  terminal_statuses: [Done, Closed, Cancelled, Duplicate]
workspace:
  root: ~/source/nomadnest-agent-runs
  # Optional: source repo to clone into each workspace (git clone)
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
  # Optional: if ticket has this GitHub label, create branch + PR after agent
  pr_label: auto-pr
poll_interval: 30
---
You are working on a NomadNest GitHub Projects ticket.

Ticket: {{ ticket.identifier }}
Title: {{ ticket.title }}
URL: {{ ticket.url }}
Repository: {{ ticket.repository }}
Provider: {{ agent.provider }}
Model: {{ agent.model }}

Description:
{{ ticket.body }}

Follow the repository instructions, create tests first for code changes, and leave a concise summary of the work performed.
