# Remote Interaction Plan: Discord / Telegram

**Date:** 2026-05-19
**Status:** Draft

## Goal

Allow NomadNest team members to trigger and monitor symphony-ruby runs through Discord or Telegram, instead of SSH'ing into a server.

## Interaction models

| Model | What it does | Complexity |
|-------|-------------|------------|
| **Notification only** | Symphony sends status updates to a channel (ticket claimed, agent done, PR created). No commands. | Low (~1 day) |
| **Command + notification** | Bot accepts commands (`/run`, `/status`, `/review`) and posts results. | Medium (~3-5 days) |
| **Full orchestration** | Bot handles ticket selection, dispatching, monitoring, PR review workflow. | High (~7-10 days) |

**Recommendation:** Start with command + notification. It gives remote control without over-engineering.

## Architecture

```
┌──────────────────────────────────────────────┐
│                  symphony-ruby               │
│                                              │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐  │
│  │  GitHub  │   │   Agent  │   │  Chat    │  │
│  │  Poller  │   │  Runner  │   │  Adapter │  │
│  └────┬─────┘   └────┬─────┘   └────┬─────┘  │
│       │              │              │        │
│       └──────────────┼──────────────┘        │
│                      │                       │
│              ┌───────┴───────┐               │
│              │  Orchestrator │               │
│              └───────────────┘               │
└──────────────────────────────────────────────┘
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
     ┌─────────┐ ┌──────────┐ ┌──────────┐
     │ Discord │ │ Telegram │ │ (future) │
     │   Bot   │ │   Bot    │ │  Slack   │
     └─────────┘ └──────────┘ └──────────┘
```

## Changes needed

### 1. Refactor symphony-ruby core (~1 day)

Extract the orchestrator into a service object that can be called from multiple entry points:

```
bin/symphony-ruby          → CLI
lib/symphony_ruby/bot.rb   → Bot (persistent, event-driven)
```

Changes:
- Add `Orchestrator#run_ticket(ticket)` as public API (already exists)
- Add `Orchestrator#run_once → [tickets_processed]` returning results
- Extract polling loop from `CLI#start` into `Poller` class
- Add a callback/hook system for status events

### 2. Chat adapter interface (~0.5 days)

```ruby
module ChatAdapter
  def on_ticket_started(ticket)
  def on_ticket_finished(ticket, success, output)
  def on_pr_created(ticket, pr_url)
  def on_error(ticket, error)
end
```

### 3. Discord bot (~2-3 days)

**Gem:** `discordrb`

**Setup:**
- Create Discord application + bot at https://discord.com/developers
- Invite bot to NomadNest server with required permissions
- Bot token in `DISCORD_BOT_TOKEN` env var

**Commands:**
| Command | What it does |
|---------|-------------|
| `/symphony run` | Poll GitHub now and run ready tickets |
| `/symphony status` | Show what's running / recent runs |
| `/symphony review` | List open PRs created by symphony |

**Notifications (in a configured channel):**
- `🎫 Ticket #176 claimed — starting agent...`
- `✅ Ticket #176 done — PR: https://github.com/.../pull/183`
- `❌ Ticket #176 failed — see logs`

**Estimate:** 2 days for bot + 1 day for integration = **3 days**

### 4. Telegram bot (~1-2 days)

**Gem:** `telegram-bot-ruby`

**Setup:**
- Create bot via @BotFather on Telegram
- Bot token in `TELEGRAM_BOT_TOKEN` env var
- Either webhook (needs public URL) or polling

**Commands:**
| Command | What it does |
|---------|-------------|
| `/run` | Poll and run ready tickets |
| `/status` | Current status |
| `/review` | Open PRs |

**Estimate:** 1 day for bot + 0.5 day integration = **1.5 days**

### 5. Shared concerns (~1 day)

- **Auth:** Only allow specific Discord roles / Telegram user IDs
- **Queue:** Prevent running the same ticket twice concurrently
- **State:** Track which tickets are running (in-memory or Redis)
- **Config:** `WORKFLOW.md` gets a `chat:` section

```yaml
chat:
  discord:
    bot_token: $DISCORD_BOT_TOKEN
    channel_id: "1234567890"
    allowed_role_ids: ["9876543210"]
  telegram:
    bot_token: $TELEGRAM_BOT_TOKEN
    chat_id: "-1001234567890"
    allowed_user_ids: ["123456789"]
```

## Estimate summary

| Phase | Days |
|-------|------|
| Core refactor (hooks + Poller) | 1 |
| Chat adapter interface | 0.5 |
| Discord bot | 3 |
| Telegram bot | 1.5 |
| Shared concerns (auth, queue, config) | 1 |
| Testing + docs | 1 |
| **Total (both platforms)** | **~8 days** |
| **Discord only** | **~5.5 days** |
| **Telegram only** | **~4 days** |

## File changes (estimated)

```
lib/symphony_ruby/
  chat_adapter.rb          # New: interface + event system
  chat/
    discord_bot.rb         # New: Discord integration
    telegram_bot.rb        # New: Telegram integration
  poller.rb                # New: extracted polling loop
  orchestrator.rb          # Modified: add event callbacks
  config.rb                # Modified: parse chat: section
bin/
  symphony-ruby            # Modified: accept --bot flag
  symphony-bot             # New: dedicated bot entry point
WORKFLOW.md                # Modified: add chat: config example
README.md                  # Modified: remote usage docs
test/
  chat_adapter_test.rb     # New
  chat/
    discord_bot_test.rb    # New
    telegram_bot_test.rb   # New
```

## What stays the same

- GitHub Projects v2 polling
- Per-ticket workspace creation + clone
- Agent command execution
- Auto-PR creation (pr_label)

## Risks

- **Bot token security:** Tokens in env vars, never in WORKFLOW.md committed to git
- **Concurrency:** Two users triggering `/run` simultaneously → needs queue
- **Long-running agents:** Discord/Telegram have timeouts on responses → use deferred replies/edits
- **Error visibility:** Agent failures must surface clearly in chat

## Next steps

1. Decide: Discord, Telegram, or both?
2. Decide: command + notification, or notification only first?
3. Create bot applications, get tokens
4. Implement in phases: core refactor → Telegram (simpler) → Discord
