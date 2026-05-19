# frozen_string_literal: true

module SymphonyRuby
  class Orchestrator
    def initialize(config:, tracker: GithubProjectsTracker.new(config: config), logger: $stdout, chat_adapter: nil)
      @config = config
      @tracker = tracker
      @logger = logger
      @chat_adapter = chat_adapter || ChatAdapter.new(logger: logger)
    end

    def run_once
      trace "Starting one orchestration pass"
      tickets = @tracker.fetch_ready_tickets
      trace "Ready tickets found: #{tickets.length}"
      tickets.first(@config.agent.max_concurrent_agents).each do |ticket|
        run_ticket(ticket)
      end
      trace "Finished one orchestration pass"
    end

    def run_forever
      loop do
        run_once
        sleep @config.poll_interval
      end
    end

    private

    def run_ticket(ticket)
      workspace_name = safe_name(ticket.identifier)
      workspace = File.join(@config.workspace.root, workspace_name)
      first_create = !File.directory?(workspace)
      trace "Preparing #{ticket.identifier}: #{ticket.title}"
      trace "Ticket: #{ticket.identifier}"
      trace "Workspace name: #{workspace_name}"
      FileUtils.mkdir_p(workspace)
      prompt_file = File.join(workspace, "PROMPT.md")
      trace "Workspace: #{workspace}"

      clone_source = @config.workspace.clone_from
      if first_create && clone_source
        trace "Cloning #{clone_source} into workspace #{workspace_name}"
        run_shell("git clone #{Shellwords.escape(clone_source)} .", workspace, {})
      end

      env = env_for(ticket, workspace, prompt_file)
      if first_create && @config.hooks.after_create
        trace "Running after_create hook for #{ticket.identifier}"
        run_shell(@config.hooks.after_create, workspace, env)
      elsif @config.hooks.after_create
        trace "Skipping after_create hook for existing workspace #{ticket.identifier}"
      end
      File.write(prompt_file, @config.render_prompt(ticket: ticket))
      trace "Prompt: #{prompt_file}"
      @tracker.mark_in_progress(ticket)
      @chat_adapter.ticket_claimed(ticket)
      @chat_adapter.agent_started(ticket)
      trace "Launching agent for #{ticket.identifier}"
      run_shell(@config.agent.command, workspace, env)
      @chat_adapter.agent_finished(ticket, true, "Agent completed")
      maybe_create_pr(ticket, workspace)
    end

    def maybe_create_pr(ticket, workspace)
      pr_label = @config.agent.pr_label
      return unless pr_label && !pr_label.empty?

      if ticket.labels.include?(pr_label)
        trace "Creating branch and PR for #{ticket.identifier} (has label: #{pr_label})"
        GitManager.new(workspace: workspace, logger: @logger).finalize(ticket)
        # gh pr create outputs the PR URL — for now, link to repo's PR list
        pr_list_url = "https://github.com/#{ticket.repository}/pulls"
        @chat_adapter.pr_created(ticket, pr_list_url)
      else
        trace "Skipping PR creation for #{ticket.identifier} (no label: #{pr_label})"
      end
    end

    def env_for(ticket, workspace, prompt_file)
      @config.agent.extra_env.merge(
        "SYMPHONY_TICKET_ID" => ticket.identifier,
        "SYMPHONY_TICKET_PROJECT_ITEM_ID" => ticket.id,
        "SYMPHONY_TICKET_TITLE" => ticket.title,
        "SYMPHONY_TICKET_URL" => ticket.url,
        "SYMPHONY_TICKET_REPOSITORY" => ticket.repository,
        "SYMPHONY_WORKSPACE" => workspace,
        "SYMPHONY_PROMPT_FILE" => prompt_file,
        "SYMPHONY_MODEL" => @config.agent.model.to_s,
        "SYMPHONY_PROVIDER" => @config.agent.provider.to_s
      )
    end

    def run_shell(command, chdir, env)
      trace command
      system(env, command, chdir: chdir, exception: true)
    end

    def trace(message)
      @logger.puts "[symphony-ruby] #{message}"
    end

    def safe_name(value)
      value.to_s.gsub(%r{[^A-Za-z0-9._-]+}, "-").gsub(/\A-+|-+\z/, "")
    end
  end
end
