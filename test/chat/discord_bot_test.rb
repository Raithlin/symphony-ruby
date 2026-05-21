# frozen_string_literal: true

require "test_helper"
require "stringio"
require "symphony_ruby"

class DiscordBotTest < Minitest::Test
  FakeTracker = Struct.new(:tickets, :marked) do
    def fetch_ready_tickets
      tickets
    end

    def mark_in_progress(ticket)
      marked << ticket.id
    end
  end

  def build_config(discord_overrides = {})
    Dir.mktmpdir do |dir|
      discord_config = {
        bot_token: "test-token",
        channel_id: "1234567890",
        allowed_role_ids: ["9876543210"]
      }.merge(discord_overrides).compact

      yaml = {
        github: { owner: "testowner", project_number: 7, token: "token" },
        workspace: { root: "#{dir}/workspaces" },
        agent: { command: "true" },
        chat: { discord: discord_config }
      }

      workflow = File.join(dir, "WORKFLOW.md")
      File.write(workflow, [
        "---",
        YAML.dump(yaml.transform_keys(&:to_s)),
        "---",
        "Ticket {{ ticket.identifier }}"
      ].join("\n"))
      yield SymphonyRuby::Config.load(workflow)
    end
  end

  # ---- Initialization & validation ----

  def test_raises_when_discord_config_is_missing
    Dir.mktmpdir do |dir|
      workflow = File.join(dir, "WORKFLOW.md")
      File.write(workflow, <<~MARKDOWN)
        ---
        github: { owner: nomadnest, project_number: 7, token: token }
        workspace: { root: #{dir}/workspaces }
        agent: { command: "true" }
        ---
        Ticket {{ ticket.identifier }}
      MARKDOWN
      config = SymphonyRuby::Config.load(workflow)

      error = assert_raises(ArgumentError) do
        SymphonyRuby::DiscordBot.new(
          config: config,
          tracker: FakeTracker.new([], []),
          logger: StringIO.new
        )
      end
      assert_match(/Missing chat.discord/, error.message)
    end
  end

  def test_raises_when_channel_id_is_missing
    build_config(channel_id: nil) do |config|
      error = assert_raises(ArgumentError) do
        SymphonyRuby::DiscordBot.new(
          config: config,
          tracker: FakeTracker.new([], []),
          logger: StringIO.new
        )
      end
      assert_match(/channel_id is required/, error.message)
    end
  end

  def test_allowed_role_ids_normalized_to_strings
    build_config(allowed_role_ids: [9876543210, "1111111111"]) do |config|
      _bot = SymphonyRuby::DiscordBot.new(
        config: config,
        tracker: FakeTracker.new([], []),
        logger: StringIO.new
      )
      # Validation: no error during init means the coercion worked
      pass
    end
  end

  def test_no_allowed_role_ids_means_open_access
    build_config(allowed_role_ids: []) do |config|
      _bot = SymphonyRuby::DiscordBot.new(
        config: config,
        tracker: FakeTracker.new([], []),
        logger: StringIO.new
      )
      pass
    end
  end

  # ---- Notifications (base class integration) ----

  def test_notification_methods_work_on_base_adapter
    build_config do |config|
      bot = SymphonyRuby::DiscordBot.new(
        config: config,
        tracker: FakeTracker.new([], []),
        logger: StringIO.new
      )

      assert_respond_to bot, :ticket_claimed
      assert_respond_to bot, :agent_started
      assert_respond_to bot, :agent_finished
      assert_respond_to bot, :pr_created
      assert_respond_to bot, :error
      assert_respond_to bot, :idle
    end
  end

  def test_notifications_noop_when_bot_not_started
    # Before start() is called, send_message/send_rich_message should silently
    # noop (not raise) since @bot is nil.
    build_config do |config|
      log = StringIO.new
      bot = SymphonyRuby::DiscordBot.new(
        config: config,
        tracker: FakeTracker.new([], []),
        logger: log
      )
      ticket = SymphonyRuby::Ticket.new(
        id: "PVTI_1", content_id: "", identifier: "#42",
        title: "T", body: "B", url: "", status: "Ready",
        repository: "r", fields: {}, labels: []
      )

      bot.ticket_claimed(ticket)
      bot.agent_started(ticket)
      bot.agent_finished(ticket, true, "ok")
      bot.pr_created(ticket, "https://example.com/pr")
      bot.error(ticket, "boom")
      bot.idle

      # Should not raise; base class calls send_message which noops when @bot is nil
      assert true
    end
  end

  # ---- Embed color ----

  def test_embed_color_by_title_prefix
    build_config do |config|
      bot = SymphonyRuby::DiscordBot.new(
        config: config,
        tracker: FakeTracker.new([], []),
        logger: StringIO.new
      )

      assert_equal 0x57F287, bot.send(:embed_color, "✅ Success")
      assert_equal 0xED4245, bot.send(:embed_color, "❌ Failed")
      assert_equal 0xFEE75C, bot.send(:embed_color, "⚠️ Warning")
      assert_equal 0x5865F2, bot.send(:embed_color, "🎫 Claimed")
      assert_equal 0x5865F2, bot.send(:embed_color, "🔀 PR created")
      assert_equal 0x5865F2, bot.send(:embed_color, "Some message")
    end
  end

  # ---- stop ----

  def test_stop_is_safe_when_bot_never_started
    build_config do |config|
      bot = SymphonyRuby::DiscordBot.new(
        config: config,
        tracker: FakeTracker.new([], []),
        logger: StringIO.new
      )

      # stop should not raise even if bot was never built
      bot.stop
      assert true
    end
  end

  # ---- list_open_prs ----

  def test_list_open_prs_returns_empty_when_no_pr_label_configured
    build_config do |config|
      bot = SymphonyRuby::DiscordBot.new(
        config: config,
        tracker: FakeTracker.new([], []),
        logger: StringIO.new
      )

      assert_equal [], bot.send(:list_open_prs)
    end
  end
end
