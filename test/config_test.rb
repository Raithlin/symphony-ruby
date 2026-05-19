require "test_helper"

class ConfigTest < Minitest::Test
  def test_loads_workflow_front_matter_and_body_with_defaults
    Dir.mktmpdir do |dir|
      workflow = File.join(dir, "WORKFLOW.md")
      File.write(workflow, <<~MARKDOWN)
        ---
        github:
          owner: nomadnest
          project_number: 7
          token: $GITHUB_TOKEN
        ticket:
          status_field: Status
          ready_status: Ready
          terminal_statuses: [Done, Closed]
        workspace:
          root: #{dir}/workspaces
        agent:
          command: ruby -e 'puts ENV["SYMPHONY_TICKET_ID"]'
        ---
        Work on {{ ticket.title }} for {{ github.owner }}.
      MARKDOWN

      ENV["GITHUB_TOKEN"] = "secret-token"
      config = SymphonyRuby::Config.load(workflow)

      assert_equal "nomadnest", config.github.owner
      assert_equal 7, config.github.project_number
      assert_equal "secret-token", config.github.token
      assert_equal "Status", config.ticket.status_field
      assert_equal "Ready", config.ticket.ready_status
      assert_equal ["Done", "Closed"], config.ticket.terminal_statuses
      assert_equal File.join(dir, "workspaces"), config.workspace.root
      assert_equal 2, config.agent.max_concurrent_agents
      assert_equal 1, config.poll_interval
      assert_includes config.render_prompt(ticket: { title: "Build search" }), "Work on Build search for nomadnest."
    ensure
      ENV.delete("GITHUB_TOKEN")
    end
  end

  def test_token_is_optional_and_falls_back_to_gh_auth_token
    Dir.mktmpdir do |dir|
      fake_bin = File.join(dir, "bin")
      FileUtils.mkdir_p(fake_bin)
      File.write(File.join(fake_bin, "gh"), <<~SH)
        #!/bin/sh
        if [ "$1" = "auth" ] && [ "$2" = "token" ]; then
          printf 'gh-token-from-cli\\n'
          exit 0
        fi
        exit 1
      SH
      FileUtils.chmod("+x", File.join(fake_bin, "gh"))

      workflow = File.join(dir, "WORKFLOW.md")
      File.write(workflow, <<~MARKDOWN)
        ---
        github:
          owner: nomadnest
          project_number: 7
        workspace:
          root: #{dir}/workspaces
        agent:
          command: "true"
        ---
        Work on {{ ticket.title }}.
      MARKDOWN

      old_path = ENV["PATH"]
      ENV["PATH"] = "#{fake_bin}:#{old_path}"
      ENV.delete("GITHUB_TOKEN")

      config = SymphonyRuby::Config.load(workflow)

      assert_equal "gh-token-from-cli", config.github.token
    ensure
      ENV["PATH"] = old_path if old_path
    end
  end
end
