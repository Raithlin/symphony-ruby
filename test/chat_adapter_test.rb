require "test_helper"
require "stringio"

class ChatAdapterTest < Minitest::Test
  # Concrete adapter that captures sent messages for assertions
  class TestAdapter < SymphonyRuby::ChatAdapter
    attr_reader :sent_messages, :sent_rich

    def initialize(logger: nil)
      super
      @sent_messages = []
      @sent_rich = []
    end

    def send_message(content, target: nil)
      @sent_messages << { content: content, target: target }
    end

    def send_rich_message(title:, body:, fields: {}, target: nil)
      @sent_rich << { title: title, body: body, fields: fields, target: target }
    end
  end

  def setup
    @ticket = SymphonyRuby::Ticket.new(
      id: "PVTI_1", content_id: "ISSUE_1", identifier: "#42",
      title: "Fix login", body: "The login is broken", url: "https://github.com/nomadnest/app/issues/42",
      status: "Ready", repository: "nomadnest/app", fields: {}, labels: []
    )
  end

  def test_ticket_claimed_notification_sends_rich_message
    adapter = TestAdapter.new
    adapter.ticket_claimed(@ticket)

    assert_equal 1, adapter.sent_rich.length
    msg = adapter.sent_rich.first
    assert_includes msg[:title], "#42"
    assert_includes msg[:title], "Fix login"
    assert_includes msg[:body], "nomadnest/app"
    assert_equal "In Progress", msg[:fields]["Status"]
  end

  def test_agent_started_notification_sends_message
    adapter = TestAdapter.new
    adapter.agent_started(@ticket)

    assert_equal 1, adapter.sent_messages.length
    assert_includes adapter.sent_messages.first[:content], "#42"
    assert_includes adapter.sent_messages.first[:content], "Fix login"
  end

  def test_agent_finished_success_notification
    adapter = TestAdapter.new
    adapter.agent_finished(@ticket, true, "All tests pass")

    assert_equal 1, adapter.sent_rich.length
    msg = adapter.sent_rich.first
    assert_includes msg[:title], "#42"
    assert_includes msg[:body], "All tests pass"
  end

  def test_agent_finished_failure_notification
    adapter = TestAdapter.new
    adapter.agent_finished(@ticket, false, "Command failed")

    msg = adapter.sent_rich.first
    assert_includes msg[:title], "FAILED"
    assert_includes msg[:body], "Command failed"
  end

  def test_pr_created_notification_includes_url
    adapter = TestAdapter.new
    adapter.pr_created(@ticket, "https://github.com/nomadnest/app/pull/183")

    assert_equal 1, adapter.sent_messages.length
    assert_includes adapter.sent_messages.first[:content], "https://github.com/nomadnest/app/pull/183"
    assert_includes adapter.sent_messages.first[:content], "#42"
  end

  def test_error_notification_contains_error_message
    adapter = TestAdapter.new
    adapter.error(@ticket, "GitHub API rate limit exceeded")

    assert_equal 1, adapter.sent_rich.length
    assert_includes adapter.sent_rich.first[:title], "Error"
    assert_includes adapter.sent_rich.first[:body], "rate limit"
  end

  def test_notification_works_even_when_concrete_adapters_do_not_override_send_methods
    log_output = StringIO.new
    # Use base class directly — send_message/send_rich_message are no-ops
    adapter = SymphonyRuby::ChatAdapter.new(logger: log_output)
    adapter.ticket_claimed(@ticket)
    # Should not raise — base class handles no-op gracefully
    assert true
  end

  def test_idle_notification
    adapter = TestAdapter.new
    adapter.idle

    assert_equal 1, adapter.sent_messages.length
    assert_includes adapter.sent_messages.first[:content], "No ready tickets"
  end

  def test_config_loads_chat_section
    Dir.mktmpdir do |dir|
      workflow = File.join(dir, "WORKFLOW.md")
      File.write(workflow, <<~MARKDOWN)
        ---
        github: { owner: nomadnest, project_number: 7, token: token }
        workspace: { root: #{dir}/workspaces }
        agent: { command: "true" }
        chat:
          discord:
            webhook_url: $DISCORD_WEBHOOK
          telegram:
            bot_token: $TELEGRAM_BOT_TOKEN
            chat_id: "-1001234567890"
        ---
        Ticket {{ ticket.identifier }}
      MARKDOWN

      ENV["DISCORD_WEBHOOK"] = "https://discord.com/api/webhooks/test/url"
      ENV["TELEGRAM_BOT_TOKEN"] = "test-telegram-token"
      config = SymphonyRuby::Config.load(workflow)

      assert config.chat.discord
      assert_equal "https://discord.com/api/webhooks/test/url", config.chat.discord[:webhook_url]
      assert config.chat.telegram
      assert_equal "test-telegram-token", config.chat.telegram[:bot_token]
      assert_equal "-1001234567890", config.chat.telegram[:chat_id]
    ensure
      ENV.delete("DISCORD_WEBHOOK")
      ENV.delete("TELEGRAM_BOT_TOKEN")
    end
  end
end
