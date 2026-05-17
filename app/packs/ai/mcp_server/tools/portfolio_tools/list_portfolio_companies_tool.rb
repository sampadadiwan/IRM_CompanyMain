# frozen_string_literal: true

# MCP tool to list portfolio companies with filtering, sorting, and aggregation.
class ListPortfolioCompaniesTool < ApplicationMcpTool
  description "List portfolio companies. Returns company name, category, city, tags. " \
              "Supports filtering via Ransack query predicates (_cont, _eq, _gt, _lt), sorting, and aggregation."

  input_schema(
    properties: {
      scope: { type: "string", description: "Predefined scope filter, e.g. 'portfolio_companies'" },
      query: { type: "object", description: "Ransack filter hash, e.g. { investor_name_cont: 'Acme' }" },
      sort: { type: "string", description: "Sort string, e.g. 'investor_name asc'" },
      limit: { type: "integer", description: "Limit number of results" },
      aggregate: { type: "string", description: "Aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on" },
      group_by_field: { type: "string", description: "Field to group results by" }
    }
  )

  def self.call(server_context:, scope: nil, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    data_manager = PortfolioAssistantDataManager.new(user: server_context[:user])

    q = (query || {}).with_indifferent_access
    q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
    q[:group_by] ||= group_by_field if group_by_field.present?

    data = data_manager.list_portfolio_companies(
      scope: scope, query: q, sort: sort,
      limit: limit, aggregate: aggregate
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
