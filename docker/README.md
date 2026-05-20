# symphony-ruby Docker setup

## Build

```bash
docker build -t symphony-ruby -f docker/Dockerfile .
```

## One-shot run

```bash
docker run --rm \
  -v $(pwd)/WORKFLOW.md:/app/WORKFLOW.md:ro \
  -v ~/.config/gh:/root/.config/gh:ro \
  -v symphony-workspace:/workspace \
  symphony-ruby --once
```

## Discord bot (persistent)

```bash
cp docker/env.example docker/.env    # edit .env with your tokens
cd docker && docker compose up -d
```

## Agent mounts

The container includes Ruby, `git`, and the GitHub CLI. Your agent must be made available — either install it in a custom image or mount the binary and its config directory from the host.

### Pi

```bash
docker run --rm \
  -v $(pwd)/WORKFLOW.md:/app/WORKFLOW.md:ro \
  -v /usr/local/bin/pi:/usr/local/bin/pi:ro \
  -v ~/.pi:/root/.pi:ro \
  -v ~/.local/share/mise:/root/.local/share/mise:ro \
  -v symphony-workspace:/workspace \
  symphony-ruby --once
```

### Claude Code

```bash
docker run --rm \
  -v $(pwd)/WORKFLOW.md:/app/WORKFLOW.md:ro \
  -v /usr/local/bin/claude:/usr/local/bin/claude:ro \
  -v ~/.claude:/root/.claude:ro \
  -v symphony-workspace:/workspace \
  symphony-ruby --once
```

### Codex

```bash
docker run --rm \
  -v $(pwd)/WORKFLOW.md:/app/WORKFLOW.md:ro \
  -v /usr/local/bin/codex:/usr/local/bin/codex:ro \
  -v ~/.codex:/root/.codex:ro \
  -v symphony-workspace:/workspace \
  symphony-ruby --once
```

## GitHub authentication

Works through the mounted `~/.config/gh` directory (if you ran `gh auth login` on the host) or by passing `GITHUB_TOKEN`:

```bash
docker run --rm -e GITHUB_TOKEN=ghp_... symphony-ruby --once
```

## Environment variables

See `env.example`. Required variables:

| Variable | Purpose |
|----------|---------|
| `DISCORD_BOT_TOKEN` | Bot token for `--bot discord` |
| `GITHUB_TOKEN` | GitHub PAT (or mount `~/.config/gh`) |
| `SYMPHONY_DRY_RUN_TICKET` | Smoke test without GitHub API calls |

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Ruby 3.4 image with git + gh CLI |
| `docker-compose.yml` | Persistent Discord bot service |
| `env.example` | Template for required environment variables |
| `.dockerignore` | Excludes git, tests, and markdown from build context |
