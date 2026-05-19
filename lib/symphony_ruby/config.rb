# frozen_string_literal: true

module SymphonyRuby
  class Config
    Github = Data.define(:owner, :project_number, :token, :owner_type, :token_source)
    TicketConfig = Data.define(:status_field, :ready_status, :in_progress_status, :terminal_statuses)
    Workspace = Data.define(:root, :clone_from)
    Agent = Data.define(:command, :max_concurrent_agents, :model, :provider, :extra_env, :pr_label)
    Hooks = Data.define(:after_create)
    Chat = Data.define(:discord, :telegram)

    attr_reader :github, :ticket, :workspace, :agent, :hooks, :chat, :poll_interval, :prompt_template

    def self.load(path)
      text = File.read(path)
      yaml_text, body = split_front_matter(text, path)
      raw = YAML.safe_load(yaml_text, permitted_classes: [Symbol], aliases: false) || {}
      new(raw, body)
    end

    def self.split_front_matter(text, path)
      match = text.match(/\A---\s*\n(.*?)\n---\s*\n?(.*)\z/m)
      raise ArgumentError, "#{path} must start with YAML front matter" unless match

      [match[1], match[2]]
    end

    def initialize(raw, body)
      @raw = symbolize(raw)
      github_raw = @raw.fetch(:github, {})
      ticket_raw = @raw.fetch(:ticket, {})
      workspace_raw = @raw.fetch(:workspace, {})
      agent_raw = @raw.fetch(:agent, {})
      hooks_raw = @raw[:hooks] || {}

      token, token_source = resolve_token(github_raw[:token])
      @github = Github.new(
        owner: required(github_raw, :owner, "github.owner"),
        project_number: Integer(required(github_raw, :project_number, "github.project_number")),
        token: token,
        owner_type: github_raw.fetch(:owner_type, "organization"),
        token_source: token_source
      )
      @ticket = TicketConfig.new(
        status_field: ticket_raw.fetch(:status_field, "Status"),
        ready_status: ticket_raw.fetch(:ready_status, "Ready"),
        in_progress_status: ticket_raw.fetch(:in_progress_status, "In Progress"),
        terminal_statuses: Array(ticket_raw.fetch(:terminal_statuses, %w[Done Closed Cancelled Duplicate]))
      )
      @workspace = Workspace.new(
        root: expand_path(required(workspace_raw, :root, "workspace.root")),
        clone_from: expand_clone_path(workspace_raw[:clone_from])
      )
      @agent = Agent.new(
        command: required(agent_raw, :command, "agent.command"),
        max_concurrent_agents: Integer(agent_raw.fetch(:max_concurrent_agents, 2)),
        model: resolve_env(agent_raw[:model]),
        provider: resolve_env(agent_raw[:provider]),
        extra_env: stringify_hash(agent_raw.fetch(:env, {})).transform_values { |value| resolve_env(value) },
        pr_label: agent_raw[:pr_label]
      )
      @hooks = Hooks.new(after_create: hooks_raw[:after_create])
      chat_raw = @raw[:chat] || {}
      @chat = Chat.new(
        discord: resolve_chat_values(symbolize(chat_raw[:discord])),
        telegram: resolve_chat_values(symbolize(chat_raw[:telegram]))
      ) if chat_raw.any?
      @chat ||= Chat.new(discord: nil, telegram: nil)
      @poll_interval = Integer(@raw.fetch(:poll_interval, 1))
      @prompt_template = body.to_s.empty? ? default_prompt : body
    end

    def render_prompt(ticket:)
      context = {
        github: @github.to_h,
        ticket: normalize(ticket),
        agent: @agent.to_h
      }
      @prompt_template.gsub(/{{\s*([\w.]+)\s*}}/) do
        lookup(context, Regexp.last_match(1).split(".")) || ""
      end
    end

    private

    def normalize(value)
      return value.to_h if value.respond_to?(:to_h)

      value
    end

    def lookup(context, parts)
      parts.reduce(context) do |memo, key|
        return nil if memo.nil?

        if memo.respond_to?(:key?) && memo.key?(key.to_sym)
          memo[key.to_sym]
        elsif memo.respond_to?(:key?) && memo.key?(key)
          memo[key]
        end
      end
    end

    def default_prompt
      "You are working on {{ ticket.identifier }}.\n\nTitle: {{ ticket.title }}\n\n{{ ticket.body }}\n"
    end

    def required(hash, key, label)
      value = hash[key]
      raise ArgumentError, "missing required config: #{label}" if value.nil? || value == ""

      value
    end

    def expand_path(path)
      File.expand_path(resolve_env(path).to_s)
    end

    def expand_clone_path(path)
      return nil if path.nil? || path.to_s.strip.empty?

      File.expand_path(resolve_env(path).to_s)
    end

    def resolve_env(value)
      return nil if value.nil?

      text = value.to_s
      return ENV.fetch(text[1..], "") if text.start_with?("$") && text.match?(/\A\$[A-Z0-9_]+\z/)

      text.gsub(/\$([A-Z0-9_]+)/) { ENV.fetch(Regexp.last_match(1), "") }
    end

    def resolve_chat_values(hash)
      return nil if hash.nil?

      hash.to_h do |key, val|
        resolved = case val
                   when Array then val.map { |v| resolve_scalar(v) }
                   else resolve_scalar(val)
                   end
        [key, resolved]
      end
    end

    def resolve_scalar(value)
      return value if value.nil?

      resolve_env(value.to_s)
    end

    def resolve_token(value)
      configured = resolve_env(value || "$GITHUB_TOKEN").to_s.strip
      return [configured, value ? "github.token" : "GITHUB_TOKEN"] unless configured.empty?

      token = gh_token.to_s.strip
      return [token, "gh auth token"] unless token.empty?

      ["", "none"]
    end

    def gh_token
      token = IO.popen(%w[gh auth token], err: File::NULL, &:read)
      return token if $?.success?

      ""
    rescue Errno::ENOENT
      ""
    end

    def symbolize(value)
      case value
      when Hash
        value.to_h { |key, val| [key.to_sym, symbolize(val)] }
      when Array
        value.map { |val| symbolize(val) }
      else
        value
      end
    end

    def stringify_hash(value)
      value.to_h { |key, val| [key.to_s, val] }
    end
  end
end
