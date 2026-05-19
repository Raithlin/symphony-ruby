# frozen_string_literal: true

module SymphonyRuby
  class ChatAdapter
    def initialize(logger: $stdout)
      @logger = logger
    end

    # --- Subclass overrides ---

    def send_message(_content, target: nil)
    end

    def send_rich_message(title:, body:, fields: {}, target: nil)
    end

    # --- Notification methods (called by orchestrator) ---

    def ticket_claimed(ticket)
      send_rich_message(
        title: "🎫 Ticket #{ticket.identifier}: #{ticket.title}",
        body: "Repository: #{ticket.repository}\nAssigned and moved to In Progress.",
        fields: {
          "Status" => "In Progress",
          "URL" => ticket.url
        }
      )
    end

    def agent_started(ticket)
      send_message("🚀 Agent started for #{ticket.identifier}: #{ticket.title}")
    end

    def agent_finished(ticket, success, output)
      if success
        send_rich_message(
          title: "✅ Ticket #{ticket.identifier} finished: #{ticket.title}",
          body: output.to_s.lines.last(10).join.strip
        )
      else
        send_rich_message(
          title: "❌ Ticket #{ticket.identifier} FAILED: #{ticket.title}",
          body: output.to_s.lines.last(10).join.strip
        )
      end
    end

    def pr_created(ticket, pr_url)
      send_message("🔀 PR for #{ticket.identifier}: #{pr_url}")
    end

    def error(ticket, message)
      send_rich_message(
        title: "⚠️ Error on #{ticket&.identifier || "unknown"}",
        body: message
      )
    end

    def idle
      send_message("💤 No ready tickets found. Polling again in #{@poll_interval || "?"}s.")
    end

    # --- Internal ---

    def poll_interval=(seconds)
      @poll_interval = seconds
    end

    private

    def trace(message)
      @logger.puts "[symphony-ruby] #{message}" if @logger
    end
  end
end
