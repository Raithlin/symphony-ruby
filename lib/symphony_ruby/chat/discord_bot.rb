# frozen_string_literal: true

require "discordrb"
require "set"

module SymphonyRuby
  class DiscordBot < ChatAdapter
    def initialize(config:, tracker:, logger: $stdout)
      super(logger: logger)
      @config = config
      @tracker = tracker
      @discord_config = config.chat.discord or
        raise ArgumentError, "Missing chat.discord section in WORKFLOW.md"
      @channel_id = @discord_config[:channel_id] or
        raise ArgumentError, "Discord channel_id is required"
      @allowed_role_ids = Array(@discord_config[:allowed_role_ids]).map(&:to_s)
      @run_mutex = Mutex.new
      @bot = nil # lazy-init in start()
    end

    # Blocks forever, processing Discord events.
    def start
      trace "Starting Discord bot..."
      build_bot
      register_commands
      @bot.run
    rescue Interrupt
      trace "Discord bot shutting down..."
      @bot&.stop
    end

    def stop
      @bot&.stop
    end

    # ---- ChatAdapter overrides ----

    def send_message(content, target: nil)
      return unless @bot

      @bot.send_message(target || @channel_id, content)
    rescue => e
      trace "Discord send_message failed: #{e.message}"
    end

    def send_rich_message(title:, body:, fields: {}, target: nil)
      return unless @bot

      embed = Discordrb::Webhooks::Embed.new(
        title: title,
        description: body,
        color: embed_color(title),
        timestamp: Time.now
      )
      fields.each do |name, value|
        embed.add_field(name: name, value: value, inline: true)
      end
      @bot.send_message(target || @channel_id, nil, false, embed)
    rescue => e
      trace "Discord send_rich_message failed: #{e.message}"
    end

    private

    # ---- Bot lifecycle ----

    def build_bot
      @bot = Discordrb::Bot.new(
        token: @discord_config[:bot_token],
        intents: Discordrb::UNPRIVILEGED_INTENTS
      )
    end

    # ---- Command registration ----

    def register_commands
      @bot.register_application_command(:symphony, "Control the symphony-ruby orchestrator") do |cmd|
        cmd.subcommand(:run, "Poll GitHub and run ready tickets")
        cmd.subcommand(:status, "Show current symphony status")
        cmd.subcommand(:review, "List open PRs created by symphony")
      end

      @bot.application_command(:symphony) do |event|
        subcommand = event.subcommand
        unless subcommand
          event.respond(content: "Usage: `/symphony run|status|review`", ephemeral: true)
          next
        end

        unless authorized?(event.user)
          event.respond(content: "⛔ You are not authorized to use symphony commands.", ephemeral: true)
          next
        end

        case subcommand
        when "run" then handle_run(event)
        when "status" then handle_status(event)
        when "review" then handle_review(event)
        end
      end
    end

    # ---- Authorization ----

    def authorized?(user)
      return true if @allowed_role_ids.empty?

      server = @bot.servers.values.first
      return false unless server

      member = server.member(user.id)
      return false unless member

      member.roles.any? { |role| @allowed_role_ids.include?(role.id.to_s) }
    end

    # ---- Command handlers ----

    def handle_run(event)
      unless @run_mutex.try_lock
        event.respond(content: "⏳ A run is already in progress. Please wait.", ephemeral: true)
        return
      end

      event.defer
      Thread.new do
        begin
          orchestrator = Orchestrator.new(
            config: @config,
            tracker: @tracker,
            chat_adapter: self
          )
          tickets = @tracker.fetch_ready_tickets

          if tickets.empty?
            event.edit_response(content: "💤 No ready tickets found.")
            return
          end

          event.edit_response(
            content: "🎫 Found #{tickets.length} ready ticket(s). Starting orchestration..."
          )
          orchestrator.run_once
          event.edit_response(content: "✅ Orchestration pass complete.")
        rescue => e
          trace "Run error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
          event.edit_response(content: "❌ Error during run: #{e.message}")
        ensure
          @run_mutex.unlock
        end
      end
    end

    def handle_status(event)
      event.respond(content: "📊 **symphony-ruby Status**\n" \
                             "• Mode: Discord bot\n" \
                             "• Channel: <##{@channel_id}>\n" \
                             "• Owner: `#{@config.github.owner}`\n" \
                             "• Project: ##{@config.github.project_number}\n" \
                             "• Agent: `#{@config.agent.provider}` / `#{@config.agent.model}`")
    end

    def handle_review(event)
      event.defer
      Thread.new do
        begin
          urls = list_open_prs
          if urls.empty?
            event.edit_response(content: "🔍 No open PRs found for `#{@config.agent.pr_label || "?"}` label.")
          else
            event.edit_response(content: "🔀 **Open symphony PRs:**\n#{urls.map { |u| "• #{u}" }.join("\n")}")
          end
        rescue => e
          trace "Review error: #{e.message}"
          event.edit_response(content: "❌ Error listing PRs: #{e.message}")
        end
      end
    end

    # ---- Helpers ----

    def list_open_prs
      pr_label = @config.agent.pr_label
      return [] unless pr_label && !pr_label.empty?

      repos = Set.new
      IO.popen(
        ["gh", "search", "prs",
         "--owner", @config.github.owner,
         "--label", pr_label,
         "--state", "open",
         "--json", "url",
         "--jq", ".[].url"],
        err: File::NULL
      ) do |io|
        io.each_line { |line| repos << line.strip }
      end
      repos.to_a
    rescue => e
      trace "PR search error: #{e.message}"
      []
    end

    def embed_color(title)
      case title
      when /\A✅/ then 0x57F287  # Green
      when /\A❌/ then 0xED4245  # Red
      when /\A⚠️/ then 0xFEE75C  # Yellow
      when /\A🎫/ then 0x5865F2  # Blurple
      when /\A🔀/ then 0x5865F2  # Blurple
      else 0x5865F2              # Default Discord blurple
      end
    end
  end
end
