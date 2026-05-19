require "test_helper"
require "stringio"
require "shellwords"

class OrchestratorTest < Minitest::Test
  FakeTracker = Struct.new(:tickets, :marked) do
    def fetch_ready_tickets
      tickets
    end

    def mark_in_progress(ticket)
      marked << ticket.id
    end
  end

  def test_runs_hook_and_agent_command_in_ticket_workspace_with_rendered_prompt
    Dir.mktmpdir do |dir|
      workflow = File.join(dir, "WORKFLOW.md")
      log = File.join(dir, "events.log")
      File.write(workflow, <<~MARKDOWN)
        ---
        github: { owner: nomadnest, project_number: 7, token: token }
        workspace: { root: #{dir}/workspaces }
        hooks:
          after_create: |
            printf 'hook:%s\\n' "$SYMPHONY_TICKET_ID" >> #{log}
        agent:
          command: |
            printf 'agent:%s:%s\\n' "$SYMPHONY_TICKET_ID" "$SYMPHONY_PROMPT_FILE" >> #{log}
          max_concurrent_agents: 1
        ---
        Ticket {{ ticket.identifier }}: {{ ticket.title }}
      MARKDOWN
      config = SymphonyRuby::Config.load(workflow)
      ticket = SymphonyRuby::Ticket.new(id: "PVTI_1", content_id: "ISSUE_1", identifier: "NN-42", title: "Ship it", body: "Body", url: "http://example", status: "Ready", repository: "nomadnest/app", fields: {}, labels: [])
      tracker = FakeTracker.new([ticket], [])

      orchestrator = SymphonyRuby::Orchestrator.new(config: config, tracker: tracker)
      orchestrator.run_once

      workspace = File.join(dir, "workspaces", "NN-42")
      prompt = File.join(workspace, "PROMPT.md")
      assert File.directory?(workspace)
      assert_equal "Ticket NN-42: Ship it\n", File.read(prompt)
      assert_equal ["PVTI_1"], tracker.marked
      assert_includes File.read(log), "hook:NN-42"
      assert_includes File.read(log), "agent:NN-42:#{prompt}"
    end
  end

  def test_after_create_hook_runs_before_prompt_is_written_so_clone_can_target_dot
    Dir.mktmpdir do |dir|
      workflow = File.join(dir, "WORKFLOW.md")
      File.write(workflow, <<~MARKDOWN)
        ---
        github: { owner: nomadnest, project_number: 7, token: token }
        workspace: { root: #{dir}/workspaces }
        hooks:
          after_create: |
            test -z "$(ls -A .)"
        agent:
          command: "true"
        ---
        Ticket {{ ticket.identifier }}
      MARKDOWN
      config = SymphonyRuby::Config.load(workflow)
      ticket = SymphonyRuby::Ticket.new(id: "PVTI_2", content_id: "ISSUE_2", identifier: "NN-43", title: "Clone", body: "Body", url: "http://example", status: "Ready", repository: "nomadnest/app", fields: {}, labels: [])

      SymphonyRuby::Orchestrator.new(config: config, tracker: FakeTracker.new([ticket], [])).run_once

      assert_equal "Ticket NN-43\n", File.read(File.join(dir, "workspaces", "NN-43", "PROMPT.md"))
    end
  end

  def test_trace_logging_shows_once_run_progress
    Dir.mktmpdir do |dir|
      workflow = File.join(dir, "WORKFLOW.md")
      File.write(workflow, <<~MARKDOWN)
        ---
        github: { owner: nomadnest, project_number: 7, token: token }
        workspace: { root: #{dir}/workspaces }
        agent:
          command: "true"
          max_concurrent_agents: 1
        ---
        Ticket {{ ticket.identifier }}
      MARKDOWN
      config = SymphonyRuby::Config.load(workflow)
      ticket = SymphonyRuby::Ticket.new(id: "PVTI_3", content_id: "ISSUE_3", identifier: "NN-44", title: "Trace", body: "Body", url: "http://example", status: "Ready", repository: "nomadnest/app", fields: {}, labels: [])
      output = StringIO.new

      SymphonyRuby::Orchestrator.new(config: config, tracker: FakeTracker.new([ticket], []), logger: output).run_once

      log = output.string
      assert_includes log, "Starting one orchestration pass"
      assert_includes log, "Ready tickets found: 1"
      assert_includes log, "Preparing NN-44: Trace"
      assert_includes log, "Workspace: #{File.join(dir, "workspaces", "NN-44")}" 
      assert_includes log, "Prompt: #{File.join(dir, "workspaces", "NN-44", "PROMPT.md")}" 
      assert_includes log, "Launching agent for NN-44"
      assert_includes log, "Finished one orchestration pass"
    end
  end

  def test_trace_logging_shows_raw_ticket_identifier_and_sanitized_workspace_name
    Dir.mktmpdir do |dir|
      workflow = File.join(dir, "WORKFLOW.md")
      File.write(workflow, <<~MARKDOWN)
        ---
        github: { owner: nomadnest, project_number: 7, token: token }
        workspace: { root: #{dir}/workspaces }
        agent:
          command: "true"
          max_concurrent_agents: 1
        ---
        Ticket {{ ticket.identifier }}
      MARKDOWN
      config = SymphonyRuby::Config.load(workflow)
      ticket = SymphonyRuby::Ticket.new(id: "PVTI_4", content_id: "ISSUE_4", identifier: "#176", title: "Hash ticket", body: "Body", url: "http://example", status: "Ready", repository: "nomadnest/app", fields: {}, labels: [])
      output = StringIO.new

      SymphonyRuby::Orchestrator.new(config: config, tracker: FakeTracker.new([ticket], []), logger: output).run_once

      assert_includes output.string, "Ticket: #176"
      assert_includes output.string, "Workspace name: 176"
      assert_includes output.string, "Workspace: #{File.join(dir, "workspaces", "176")}" 
    end
  end

  def test_creates_branch_and_pr_when_ticket_has_pr_label
    Dir.mktmpdir do |dir|
      fake_bin = File.join(dir, "bin")
      FileUtils.mkdir_p(fake_bin)

      git_log = File.join(dir, "git-calls.log")
      FileUtils.touch(git_log)
      File.write(File.join(fake_bin, "git"), <<~SH)
        #!/bin/sh
        echo "git $*" >> #{git_log}
        case "$1" in
          "rev-parse") echo "#{dir}/workspaces/45/.git" ;;
          "push") exit 0 ;;
        esac
        exit 0
      SH
      FileUtils.chmod("+x", File.join(fake_bin, "git"))

      gh_log = File.join(dir, "gh-calls.log")
      File.write(File.join(fake_bin, "gh"), <<~SH)
        #!/bin/sh
        echo "gh $*" >> #{gh_log}
        exit 0
      SH
      FileUtils.chmod("+x", File.join(fake_bin, "gh"))

      workflow = File.join(dir, "WORKFLOW.md")
      File.write(workflow, <<~MARKDOWN)
        ---
        github: { owner: nomadnest, project_number: 7, token: token }
        workspace: { root: #{dir}/workspaces }
        agent:
          command: "true"
          max_concurrent_agents: 1
          pr_label: auto-pr
        ---
        Ticket {{ ticket.identifier }}
      MARKDOWN
      config = SymphonyRuby::Config.load(workflow)
      ticket = SymphonyRuby::Ticket.new(
        id: "PVTI_5", content_id: "ISSUE_5", identifier: "#45", title: "Create PR test",
        body: "Testing PR creation", url: "http://example", status: "Ready",
        repository: "nomadnest/app", fields: {}, labels: ["auto-pr", "bug"]
      )
      output = StringIO.new

      old_path = ENV["PATH"]
      ENV["PATH"] = "#{fake_bin}:#{old_path}"

      SymphonyRuby::Orchestrator.new(config: config, tracker: FakeTracker.new([ticket], []), logger: output).run_once

      ENV["PATH"] = old_path

      git_commands = File.read(git_log)
      assert_includes git_commands, "git checkout -b"
      assert_includes git_commands, "create-pr-test"
      assert_includes git_commands, "git push"

      gh_commands = File.read(gh_log)
      assert_includes gh_commands, "gh pr create"
      assert_includes gh_commands, "Create PR test"
      assert_includes output.string, "Creating branch and PR for #45 (has label: auto-pr)"
    end
  end

  def test_auto_clones_from_configured_source_before_hook
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source-repo")
      FileUtils.mkdir_p(File.join(source, "app"))
      File.write(File.join(source, "Gemfile"), "gem 'rails'")
      # Set up as a git repo so clone works
      system("git init -b main #{Shellwords.escape(source)} > /dev/null 2>&1")
      system("git -C #{Shellwords.escape(source)} add -A > /dev/null 2>&1")
      system("git -C #{Shellwords.escape(source)} commit -m init > /dev/null 2>&1")

      workflow = File.join(dir, "WORKFLOW.md")
      File.write(workflow, <<~MARKDOWN)
        ---
        github: { owner: nomadnest, project_number: 7, token: token }
        workspace:
          root: #{dir}/workspaces
          clone_from: #{source}
        agent:
          command: "true"
          max_concurrent_agents: 1
        ---
        Ticket {{ ticket.identifier }}
      MARKDOWN
      config = SymphonyRuby::Config.load(workflow)
      ticket = SymphonyRuby::Ticket.new(id: "PVTI_7", content_id: "ISSUE_7", identifier: "#99", title: "Clone test", body: "Body", url: "http://example", status: "Ready", repository: "nomadnest/app", fields: {}, labels: [])
      output = StringIO.new

      SymphonyRuby::Orchestrator.new(config: config, tracker: FakeTracker.new([ticket], []), logger: output).run_once

      ws = File.join(dir, "workspaces", "99")
      assert File.exist?(File.join(ws, "Gemfile"))
      assert_includes output.string, "Cloning #{source} into workspace 99"
    end
  end

  def test_skips_pr_creation_when_ticket_lacks_pr_label
    Dir.mktmpdir do |dir|
      fake_bin = File.join(dir, "bin")
      FileUtils.mkdir_p(fake_bin)
      git_log = File.join(dir, "git-calls.log")
      FileUtils.touch(git_log)
      File.write(File.join(fake_bin, "git"), "#!/bin/sh\necho FAIL >> #{git_log}\nexit 1\n")
      FileUtils.chmod("+x", File.join(fake_bin, "git"))

      workflow = File.join(dir, "WORKFLOW.md")
      File.write(workflow, <<~MARKDOWN)
        ---
        github: { owner: nomadnest, project_number: 7, token: token }
        workspace: { root: #{dir}/workspaces }
        agent:
          command: "true"
          max_concurrent_agents: 1
          pr_label: auto-pr
        ---
        Ticket {{ ticket.identifier }}
      MARKDOWN
      config = SymphonyRuby::Config.load(workflow)
      ticket = SymphonyRuby::Ticket.new(
        id: "PVTI_6", content_id: "ISSUE_6", identifier: "#46", title: "No PR",
        body: "No", url: "http://example", status: "Ready",
        repository: "nomadnest/app", fields: {}, labels: ["bug"]
      )
      output = StringIO.new

      old_path = ENV["PATH"]
      ENV["PATH"] = "#{fake_bin}:#{old_path}"

      SymphonyRuby::Orchestrator.new(config: config, tracker: FakeTracker.new([ticket], []), logger: output).run_once

      ENV["PATH"] = old_path

      assert_empty File.read(git_log)
      assert_includes output.string, "Skipping PR creation for #46 (no label: auto-pr)"
    end
  end
end
