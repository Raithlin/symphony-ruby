# Discord bot

Symphony Ruby can run as a Discord bot, accepting slash commands and posting notifications to a configured channel.

## Setup

1. Create a Discord application + bot at [discord.com/developers/applications](https://discord.com/developers/applications)
2. Go to **Bot** → **Reset Token** and copy the token
3. Enable **Developer Mode** in Discord (User Settings → Advanced), right-click your target notification channel → **Copy ID**
4. (Optional) Copy role IDs the same way if you want to restrict who can use commands
5. Invite the bot to your server. Use the OAuth2 URL Generator on the app page:
   - **Scopes:** `bot`, `applications.commands`
   - **Permissions:** `Send Messages`, `Embed Links`, `Use Slash Commands`

## Configuration

Add a `chat.discord` section to `WORKFLOW.md`:

```yaml
chat:
  discord:
    bot_token: $DISCORD_BOT_TOKEN
    channel_id: "1234567890"
    allowed_role_ids: ["9876543210"]  # optional
```

| Key | Required | Description |
|-----|----------|-------------|
| `bot_token` | Yes | Bot token from the Developer Portal (or `$DISCORD_BOT_TOKEN` env var) |
| `channel_id` | Yes | Target text channel ID for notifications |
| `allowed_role_ids` | No | If set, only users with one of these role IDs can use slash commands |

## Running

```bash
export DISCORD_BOT_TOKEN=your_token_here
bin/symphony-ruby --bot discord
```

The bot runs persistently, listening for slash commands and posting notifications to the configured channel.

## Slash commands

| Command | What it does |
|---------|-------------|
| `/symphony run` | Polls GitHub for ready tickets and runs the orchestrator |
| `/symphony status` | Shows current owner, project, provider/model, channel |
| `/symphony review` | Lists open PRs matching the configured `pr_label` |

### `/symphony run`

Polls GitHub Projects v2 for tickets in the `ticket.ready_status` state. If any are found, creates workspaces, renders prompts, and launches the configured agent. Uses a mutex to prevent concurrent runs — if one run is already in progress, the command returns `⏳ A run is already in progress.`

Since agent runs can take a long time, the bot uses Discord's deferred response pattern: it acknowledges the interaction immediately, then edits the response once the orchestrator finishes.

### `/symphony status`

Prints a quick summary:

```
📊 symphony-ruby Status
• Mode: Discord bot
• Channel: #general
• Owner: `NomadNest`
• Project: #7
• Agent: `deepseek` / `deepseek-v4-pro`
```

### `/symphony review`

Searches GitHub for open PRs with the configured `agent.pr_label` in the configured owner. Runs `gh search prs` under the hood.

## Authorization

If `allowed_role_ids` is configured, the bot checks the user's roles on the first server it shares with them. The user must have at least one role whose ID appears in the list. If the list is empty or omitted, all users can use commands.

## Notifications

The bot posts to the configured channel when tickets progress through the orchestration pipeline:

| Event | Discord message |
|-------|----------------|
| Ticket claimed | Rich embed with 🎫 title, repo, status |
| Agent started | "🚀 Agent started for #42: Title" |
| Agent finished | ✅ Green embed or ❌ Red embed with last 10 lines of output |
| PR created | "🔀 PR for #42: url" |
| Error | ⚠️ Yellow embed with error message |
| No ready tickets | "💤 No ready tickets found" |

Embed colors match the event severity:
- ✅ → `#57F287` (green)
- ❌ → `#ED4245` (red)
- ⚠️ → `#FEE75C` (yellow)
- 🎫/🔀 → `#5865F2` (blurple — Discord's brand color)

## Docker

The `docker-compose.yml` in `docker/` is pre-configured for the Discord bot. See [docker/README.md](../docker/README.md).

## Implementation

- **Source:** `lib/symphony_ruby/discord_bot.rb`
- **Base class:** `ChatAdapter` (`lib/symphony_ruby/chat_adapter.rb`)
- **Tests:** `test/chat/discord_bot_test.rb`

The bot uses the `discordrb` gem (v3.x). It lazily initializes the `Discordrb::Bot` instance in `start()` so tests can exercise config validation and helper methods without a real token.
