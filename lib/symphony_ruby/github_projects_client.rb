# frozen_string_literal: true

module SymphonyRuby
  class GithubProjectsClient
    ENDPOINT = URI("https://api.github.com/graphql")

    PROJECT_ITEM_SELECTION = <<~GRAPHQL
      projectV2(number: $number) {
        items(first: 50, after: $cursor) {
          pageInfo { hasNextPage endCursor }
          nodes {
            id
            content {
              __typename
              ... on Issue { id number title body url repository { nameWithOwner } labels(first: 20) { nodes { name } } assignees(first: 20) { nodes { login } } }
              ... on PullRequest { id number title body url repository { nameWithOwner } labels(first: 20) { nodes { name } } assignees(first: 20) { nodes { login } } }
              ... on DraftIssue { id title body }
            }
            fieldValues(first: 30) {
              nodes {
                __typename
                ... on ProjectV2ItemFieldTextValue { text field { ... on ProjectV2FieldCommon { name } } }
                ... on ProjectV2ItemFieldSingleSelectValue { name field { ... on ProjectV2FieldCommon { name } } }
                ... on ProjectV2ItemFieldNumberValue { number field { ... on ProjectV2FieldCommon { name } } }
                ... on ProjectV2ItemFieldDateValue { date field { ... on ProjectV2FieldCommon { name } } }
              }
            }
          }
        }
      }
    GRAPHQL

    ORGANIZATION_PROJECT_QUERY = <<~GRAPHQL
      query($owner: String!, $number: Int!, $cursor: String) {
        organization(login: $owner) {
          #{PROJECT_ITEM_SELECTION}
        }
      }
    GRAPHQL

    USER_PROJECT_QUERY = <<~GRAPHQL
      query($owner: String!, $number: Int!, $cursor: String) {
        user(login: $owner) {
          #{PROJECT_ITEM_SELECTION}
        }
      }
    GRAPHQL

    PROJECT_FIELDS_SELECTION = <<~GRAPHQL
      projectV2(number: $number) {
        id
        fields(first: 50) {
          nodes {
            __typename
            ... on ProjectV2FieldCommon { id name }
            ... on ProjectV2SingleSelectField { id name options { id name } }
          }
        }
      }
    GRAPHQL

    ORGANIZATION_PROJECT_FIELDS_QUERY = <<~GRAPHQL
      query($owner: String!, $number: Int!) {
        organization(login: $owner) {
          #{PROJECT_FIELDS_SELECTION}
        }
      }
    GRAPHQL

    USER_PROJECT_FIELDS_QUERY = <<~GRAPHQL
      query($owner: String!, $number: Int!) {
        user(login: $owner) {
          #{PROJECT_FIELDS_SELECTION}
        }
      }
    GRAPHQL

    VIEWER_QUERY = <<~GRAPHQL
      query {
        viewer { id login }
      }
    GRAPHQL

    ADD_ASSIGNEES_MUTATION = <<~GRAPHQL
      mutation($assignableId: ID!, $assigneeIds: [ID!]!) {
        addAssigneesToAssignable(input: { assignableId: $assignableId, assigneeIds: $assigneeIds }) {
          clientMutationId
        }
      }
    GRAPHQL

    UPDATE_PROJECT_STATUS_MUTATION = <<~GRAPHQL
      mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
        updateProjectV2ItemFieldValue(input: {
          projectId: $projectId,
          itemId: $itemId,
          fieldId: $fieldId,
          value: { singleSelectOptionId: $optionId }
        }) {
          projectV2Item { id }
        }
      }
    GRAPHQL

    ADD_COMMENT_MUTATION = <<~GRAPHQL
      mutation($subjectId: ID!, $body: String!) {
        addComment(input: { subjectId: $subjectId, body: $body }) {
          commentEdge { node { id } }
        }
      }
    GRAPHQL

    def initialize(token:, http: nil, logger: nil)
      @token = token
      @http = http || method(:default_http)
      @logger = logger
    end

    def fetch_tickets(owner:, project_number:, status_field:, ready_status:, owner_type: "organization", assigned_to_current_user_only: false)
      query, root_key = query_for(owner_type)
      viewer_login = current_viewer_login if assigned_to_current_user_only

      tickets = []
      cursor = nil
      loop do
        trace "Querying GitHub Projects v2 owner=#{owner} owner_type=#{owner_type} project_number=#{project_number} cursor=#{cursor || "<first>"}"
        data = graphql(query, owner: owner, number: project_number, cursor: cursor)
        items = data.dig(root_key, "projectV2", "items") || {}
        Array(items["nodes"]).each do |node|
          fields = fields_for(node)
          trace "Project item #{node.fetch("id")} status=#{fields[status_field].inspect} title=#{node.dig("content", "title").inspect}"
          next unless fields[status_field] == ready_status
          next if assigned_to_current_user_only && !assigned_to?(node, viewer_login)

          tickets << ticket_for(node, fields, status_field)
        end
        page = items["pageInfo"] || {}
        break unless page["hasNextPage"]

        cursor = page["endCursor"]
      end
      tickets
    end

    def claim_ticket(ticket, owner:, owner_type:, project_number:, status_field:, in_progress_status:)
      viewer = graphql(VIEWER_QUERY, {})
      viewer_id = viewer.dig("viewer", "id")
      viewer_login = viewer.dig("viewer", "login")

      if ticket.content_id.to_s.empty?
        trace "Skipping assignment for #{ticket.identifier}: project item has no assignable content id"
      else
        trace "Assigning #{ticket.identifier} to #{viewer_login}"
        graphql(ADD_ASSIGNEES_MUTATION, assignableId: ticket.content_id, assigneeIds: [viewer_id])
      end

      project_id, field_id, option_id = status_field_ids(
        owner: owner,
        owner_type: owner_type,
        project_number: project_number,
        status_field: status_field,
        status_value: in_progress_status
      )
      trace "Moving #{ticket.identifier} to #{status_field}=#{in_progress_status}"
      graphql(UPDATE_PROJECT_STATUS_MUTATION, projectId: project_id, itemId: ticket.id, fieldId: field_id, optionId: option_id)
    end

    def request_clarification(ticket, body, owner:, owner_type:, project_number:, status_field:, needs_clarification_status:)
      if ticket.content_id.to_s.empty?
        trace "Skipping clarification comment for #{ticket.identifier}: project item has no commentable content id"
      else
        trace "Commenting clarification request on #{ticket.identifier}"
        graphql(ADD_COMMENT_MUTATION, subjectId: ticket.content_id, body: clarification_comment(body))
      end

      project_id, field_id, option_id = status_field_ids(
        owner: owner,
        owner_type: owner_type,
        project_number: project_number,
        status_field: status_field,
        status_value: needs_clarification_status
      )
      trace "Moving #{ticket.identifier} to #{status_field}=#{needs_clarification_status}"
      graphql(UPDATE_PROJECT_STATUS_MUTATION, projectId: project_id, itemId: ticket.id, fieldId: field_id, optionId: option_id)
    end

    private

    def query_for(owner_type)
      case owner_type
      when "organization"
        [ORGANIZATION_PROJECT_QUERY, "organization"]
      when "user"
        [USER_PROJECT_QUERY, "user"]
      else
        raise ArgumentError, "github.owner_type must be 'organization' or 'user'"
      end
    end

    def fields_query_for(owner_type)
      case owner_type
      when "organization"
        [ORGANIZATION_PROJECT_FIELDS_QUERY, "organization"]
      when "user"
        [USER_PROJECT_FIELDS_QUERY, "user"]
      else
        raise ArgumentError, "github.owner_type must be 'organization' or 'user'"
      end
    end

    def status_field_ids(owner:, owner_type:, project_number:, status_field:, status_value:)
      query, root_key = fields_query_for(owner_type)
      data = graphql(query, owner: owner, number: project_number)
      project = data.dig(root_key, "projectV2") || {}
      field = Array(project.dig("fields", "nodes")).find { |node| node && node["name"] == status_field }
      raise "GitHub Project field not found: #{status_field}" unless field

      option = Array(field["options"]).find { |item| item["name"] == status_value }
      raise "GitHub Project status option not found: #{status_value}" unless option

      [project.fetch("id"), field.fetch("id"), option.fetch("id")]
    end

    def trace(message)
      @logger&.puts "[symphony-ruby] #{message}"
    end

    def current_viewer_login
      viewer = graphql(VIEWER_QUERY, {})
      viewer.dig("viewer", "login").to_s
    end

    def assigned_to?(node, login)
      assignees = Array(node.dig("content", "assignees", "nodes"))
      assignees.any? { |assignee| assignee["login"].to_s.casecmp?(login) }
    end

    def clarification_comment(body)
      <<~COMMENT.strip
        **Symphony needs clarification before continuing:**

        #{body}
      COMMENT
    end

    def graphql(query, variables)
      request = Net::HTTP::Post.new(ENDPOINT)
      request["Authorization"] = "Bearer #{@token}"
      request["Accept"] = "application/vnd.github+json"
      request["Content-Type"] = "application/json"
      request.body = JSON.dump(query: query, variables: variables)
      response = @http.call(request)
      raise "GitHub GraphQL request failed: HTTP #{response.code}: #{response.body}" unless response.code.to_i.between?(200, 299)

      payload = JSON.parse(response.body)
      raise "GitHub GraphQL errors: #{payload.fetch("errors").inspect}" if payload["errors"]

      payload.fetch("data")
    end

    def default_http(request)
      Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true) { |http| http.request(request) }
    end

    def fields_for(node)
      Array(node.dig("fieldValues", "nodes")).each_with_object({}) do |field_value, memo|
        name = field_value.dig("field", "name")
        next unless name

        memo[name] = field_value["name"] || field_value["text"] || field_value["number"] || field_value["date"]
      end
    end

    def ticket_for(node, fields, status_field)
      content = node["content"] || {}
      number = content["number"]
      identifier = number ? "##{number}" : node.fetch("id")
      labels = Array(content.dig("labels", "nodes")).map { |node| node["name"] }.compact
      Ticket.new(
        id: node.fetch("id"),
        content_id: content["id"].to_s,
        identifier: identifier,
        title: content["title"].to_s,
        body: content["body"].to_s,
        url: content["url"].to_s,
        status: fields[status_field].to_s,
        repository: content.dig("repository", "nameWithOwner").to_s,
        fields: fields,
        labels: labels
      )
    end
  end

  class GithubProjectsTracker
    def initialize(config:, client: nil)
      @config = config
      @client = client || GithubProjectsClient.new(token: config.github.token)
    end

    def fetch_ready_tickets
      @client.fetch_tickets(
        owner: @config.github.owner,
        project_number: @config.github.project_number,
        status_field: @config.ticket.status_field,
        ready_status: @config.ticket.ready_status,
        owner_type: @config.github.owner_type,
        assigned_to_current_user_only: @config.ticket.assigned_to_current_user_only
      )
    end

    def mark_in_progress(ticket)
      @client.claim_ticket(
        ticket,
        owner: @config.github.owner,
        owner_type: @config.github.owner_type,
        project_number: @config.github.project_number,
        status_field: @config.ticket.status_field,
        in_progress_status: @config.ticket.in_progress_status
      )
    end

    def request_clarification(ticket, body)
      @client.request_clarification(
        ticket,
        body,
        owner: @config.github.owner,
        owner_type: @config.github.owner_type,
        project_number: @config.github.project_number,
        status_field: @config.ticket.status_field,
        needs_clarification_status: @config.ticket.needs_clarification_status
      )
    end
  end
end
