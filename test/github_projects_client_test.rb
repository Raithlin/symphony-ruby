require "test_helper"

class GithubProjectsClientTest < Minitest::Test
  FakeResponse = Struct.new(:code, :body)

  def test_fetch_ready_tickets_maps_project_items
    http = lambda do |request|
      body = JSON.parse(request.body)
      assert_includes body.fetch("query"), "ProjectV2"
      assert_equal "nomadnest", body.dig("variables", "owner")
      assert_equal 7, body.dig("variables", "number")

      FakeResponse.new("200", JSON.dump({
        data: {
          organization: {
            projectV2: {
              items: {
                pageInfo: { hasNextPage: false, endCursor: nil },
                nodes: [{
                  id: "PVTI_1",
                  content: { __typename: "Issue", id: "ISSUE_42", number: 42, title: "Add booking", body: "Details", url: "https://github.com/nomadnest/app/issues/42", repository: { nameWithOwner: "nomadnest/app" } },
                  fieldValues: { nodes: [
                    { __typename: "ProjectV2ItemFieldSingleSelectValue", name: "Ready", field: { name: "Status" } },
                    { __typename: "ProjectV2ItemFieldTextValue", text: "High", field: { name: "Priority" } }
                  ] }
                }]
              }
            }
          }
        }
      }))
    end

    client = SymphonyRuby::GithubProjectsClient.new(token: "ghp_test", http: http)
    tickets = client.fetch_tickets(owner: "nomadnest", project_number: 7, status_field: "Status", ready_status: "Ready")

    assert_equal 1, tickets.length
    ticket = tickets.first
    assert_equal "PVTI_1", ticket.id
    assert_equal "#42", ticket.identifier
    assert_equal "Add booking", ticket.title
    assert_equal "Ready", ticket.status
    assert_equal "nomadnest/app", ticket.repository
    assert_equal "ISSUE_42", ticket.content_id
  end

  def test_fetch_ready_tickets_supports_user_owned_projects
    http = lambda do |request|
      body = JSON.parse(request.body)
      assert_includes body.fetch("query"), "user(login: $owner)"
      assert_equal "Raithlin", body.dig("variables", "owner")

      FakeResponse.new("200", JSON.dump({
        data: {
          user: {
            projectV2: {
              items: {
                pageInfo: { hasNextPage: false, endCursor: nil },
                nodes: [{
                  id: "PVTI_USER_1",
                  content: { __typename: "Issue", id: "ISSUE_8", number: 8, title: "User project item", body: "Details", url: "https://github.com/NomadNest/nomadnest/issues/8", repository: { nameWithOwner: "NomadNest/nomadnest" } },
                  fieldValues: { nodes: [
                    { __typename: "ProjectV2ItemFieldSingleSelectValue", name: "Ready", field: { name: "Status" } }
                  ] }
                }]
              }
            }
          }
        }
      }))
    end

    client = SymphonyRuby::GithubProjectsClient.new(token: "ghp_test", http: http)
    tickets = client.fetch_tickets(owner: "Raithlin", project_number: 1, status_field: "Status", ready_status: "Ready", owner_type: "user")

    assert_equal 1, tickets.length
    assert_equal "PVTI_USER_1", tickets.first.id
    assert_equal "#8", tickets.first.identifier
  end

  def test_claim_ticket_assigns_content_to_viewer_and_moves_project_item_to_in_progress
    requests = []
    http = lambda do |request|
      payload = JSON.parse(request.body)
      requests << payload
      query = payload.fetch("query")

      if query.include?("viewer")
        FakeResponse.new("200", JSON.dump(data: { viewer: { id: "USER_1", login: "raithlin" } }))
      elsif query.include?("fields(first: 50)")
        FakeResponse.new("200", JSON.dump(data: {
          user: {
            projectV2: {
              id: "PROJECT_1",
              fields: {
                nodes: [{
                  __typename: "ProjectV2SingleSelectField",
                  id: "FIELD_STATUS",
                  name: "Status",
                  options: [{ id: "OPT_READY", name: "Ready" }, { id: "OPT_PROGRESS", name: "In Progress" }]
                }]
              }
            }
          }
        }))
      elsif query.include?("addAssigneesToAssignable")
        assert_equal "ISSUE_8", payload.dig("variables", "assignableId")
        assert_equal ["USER_1"], payload.dig("variables", "assigneeIds")
        FakeResponse.new("200", JSON.dump(data: { addAssigneesToAssignable: { clientMutationId: nil } }))
      elsif query.include?("updateProjectV2ItemFieldValue")
        assert_equal "PROJECT_1", payload.dig("variables", "projectId")
        assert_equal "PVTI_USER_1", payload.dig("variables", "itemId")
        assert_equal "FIELD_STATUS", payload.dig("variables", "fieldId")
        assert_equal "OPT_PROGRESS", payload.dig("variables", "optionId")
        FakeResponse.new("200", JSON.dump(data: { updateProjectV2ItemFieldValue: { projectV2Item: { id: "PVTI_USER_1" } } }))
      else
        raise "unexpected query: #{query}"
      end
    end

    client = SymphonyRuby::GithubProjectsClient.new(token: "ghp_test", http: http)
    ticket = SymphonyRuby::Ticket.new(id: "PVTI_USER_1", content_id: "ISSUE_8", identifier: "#8", title: "User project item", body: "Details", url: "https://github.com/NomadNest/nomadnest/issues/8", status: "Ready", repository: "NomadNest/nomadnest", fields: { "Status" => "Ready" }, labels: [])

    client.claim_ticket(ticket, owner: "Raithlin", owner_type: "user", project_number: 1, status_field: "Status", in_progress_status: "In Progress")

    assert_equal 4, requests.length
  end

  def test_tracker_marks_ticket_in_progress_using_config
    calls = []
    client = Object.new
    client.define_singleton_method(:claim_ticket) { |ticket, args| calls << [ticket, args] }
    config = SymphonyRuby::Config.new({
      github: { owner: "Raithlin", owner_type: "user", project_number: 1, token: "token" },
      ticket: { status_field: "Status", in_progress_status: "In Progress" },
      workspace: { root: Dir.tmpdir },
      agent: { command: "true" }
    }, "Prompt")
    ticket = SymphonyRuby::Ticket.new(id: "PVTI_USER_1", content_id: "ISSUE_8", identifier: "#8", title: "User project item", body: "Details", url: "https://github.com/NomadNest/nomadnest/issues/8", status: "Ready", repository: "NomadNest/nomadnest", fields: { "Status" => "Ready" }, labels: [])

    SymphonyRuby::GithubProjectsTracker.new(config: config, client: client).mark_in_progress(ticket)

    assert_equal ticket, calls.dig(0, 0)
    assert_equal({ owner: "Raithlin", owner_type: "user", project_number: 1, status_field: "Status", in_progress_status: "In Progress" }, calls.dig(0, 1))
  end
end
