# frozen_string_literal: true

require "test_helper"
require "stringio"

class GitManagerTest < Minitest::Test
  def test_pushes_to_github_repo_from_ticket_when_origin_is_local_clone
    Dir.mktmpdir do |dir|
      workspace = File.join(dir, "workspace")
      fake_bin = File.join(dir, "bin")
      FileUtils.mkdir_p([workspace, fake_bin])

      git_log = File.join(dir, "git-calls.log")
      File.write(File.join(fake_bin, "git"), <<~SH)
        #!/bin/sh
        echo "git $*" >> #{git_log}
        case "$1 $2 $3" in
          "-C #{workspace} status") exit 0 ;;
          "-C #{workspace} rev-parse") echo "#{workspace}/.git"; exit 0 ;;
          "remote get-url origin") echo "#{dir}/source-repo"; exit 0 ;;
          "remote get-url symphony-pr") exit 2 ;;
          *) exit 0 ;;
        esac
      SH
      FileUtils.chmod("+x", File.join(fake_bin, "git"))

      gh_log = File.join(dir, "gh-calls.log")
      File.write(File.join(fake_bin, "gh"), <<~SH)
        #!/bin/sh
        echo "gh $*" >> #{gh_log}
        exit 0
      SH
      FileUtils.chmod("+x", File.join(fake_bin, "gh"))

      ticket = SymphonyRuby::Ticket.new(
        id: "PVTI_5", content_id: "ISSUE_5", identifier: "#45", title: "Create PR test",
        body: "Testing PR creation", url: "http://example", status: "Ready",
        repository: "nomadnest/app", fields: {}, labels: ["auto-pr"]
      )

      old_path = ENV["PATH"]
      ENV["PATH"] = "#{fake_bin}:#{old_path}"

      SymphonyRuby::GitManager.new(workspace: workspace, logger: StringIO.new).finalize(ticket)

      git_commands = File.read(git_log)
      assert_includes git_commands, "git remote add symphony-pr git@github.com:nomadnest/app.git"
      assert_includes git_commands, "git push -u symphony-pr 45-create-pr-test"

      gh_commands = File.read(gh_log)
      assert_includes gh_commands, "gh pr create"
      assert_includes gh_commands, "--repo nomadnest/app"
      assert_includes gh_commands, "--head 45-create-pr-test"
    ensure
      ENV["PATH"] = old_path
    end
  end
end
