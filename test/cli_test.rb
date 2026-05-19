require "test_helper"

class CliTest < Minitest::Test
  def test_cli_runs_once_with_dry_run_tracker
    Dir.mktmpdir do |dir|
      workflow = File.join(dir, "WORKFLOW.md")
      log = File.join(dir, "events.log")
      File.write(workflow, <<~MARKDOWN)
        ---
        github: { owner: nomadnest, project_number: 7, token: token }
        workspace: { root: #{dir}/workspaces }
        agent:
          provider: openai
          model: gpt-5.5
          command: |
            printf '%s:%s:%s\\n' "$SYMPHONY_PROVIDER" "$SYMPHONY_MODEL" "$SYMPHONY_TICKET_ID" >> #{log}
        ---
        Build {{ ticket.title }}
      MARKDOWN

      assert system({ "SYMPHONY_DRY_RUN_TICKET" => "NN-1|Demo task" }, "ruby", "-Ilib", "bin/symphony-ruby", workflow, "--once", chdir: File.expand_path("..", __dir__))
      assert_equal "openai:gpt-5.5:NN-1\n", File.read(log)
    end
  end
end
