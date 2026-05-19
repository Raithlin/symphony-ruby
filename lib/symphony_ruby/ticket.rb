# frozen_string_literal: true

module SymphonyRuby
  Ticket = Data.define(:id, :content_id, :identifier, :title, :body, :url, :status, :repository, :fields, :labels) do
    def to_h
      {
        id: id,
        content_id: content_id,
        identifier: identifier,
        title: title,
        body: body,
        url: url,
        status: status,
        repository: repository,
        fields: fields,
        labels: labels
      }
    end
  end
end
