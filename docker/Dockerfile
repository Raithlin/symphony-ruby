# Build:  docker build -t symphony-ruby .
# Run:    docker run --rm -v $(pwd)/WORKFLOW.md:/app/WORKFLOW.md symphony-ruby
# Bot:    docker run --rm --env-file .env -v $(pwd)/WORKFLOW.md:/app/WORKFLOW.md symphony-ruby --bot discord

FROM docker.io/library/ruby:3.4-slim

LABEL org.opencontainers.image.title="symphony-ruby"
LABEL org.opencontainers.image.description="GitHub Projects v2 orchestrator for configurable coding agents"

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
     -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
     > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock symphony-ruby.gemspec ./
COPY lib/ ./lib/
COPY bin/ ./bin/

RUN bundle install && \
    bundle clean --force

# Workspace root and agent runs go here — mount a volume in production.
RUN mkdir -p /workspace
VOLUME /workspace

# WORKFLOW.md is mounted at runtime.
# GitHub auth: mount ~/.config/gh or set GITHUB_TOKEN / DISCORD_BOT_TOKEN.

ENTRYPOINT ["ruby", "/app/bin/symphony-ruby"]
CMD ["--bot", "discord"]
