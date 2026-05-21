# frozen_string_literal: true

# MCP tool to list portfolio companies with filtering, sorting, and aggregation.
class ListPortfolioCompaniesTool < ApplicationMcpTool
  description "List all portfolio companies with optional Ransack filtering, ordering, and limiting. " \
              "START HERE for portfolio data — use this tool first to discover portfolio company IDs, then drill into investments, KPIs, valuations, etc. " \
              "Construct a query hash using available attributes and predicates. " \
              "Attributes: investor_name, city, tag_list. " \
              "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
              "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Examples: sort: 'investor_name asc', limit: 10."

  input_schema(
    properties: {
      scope: { type: "string", description: "Filter by a predefined scope: 'portfolio_companies', 'not_portfolio_companies', 'advisors', 'rms'" },
      query: { type: "object", description: "Ransack query hash, e.g. { investor_name_cont: 'Acme', tag_list_cont: 'Tech' }. Combine attribute + predicate." },
      sort: { type: "string", description: "Sort string, e.g. 'investor_name asc'. Maps to Ransack `s`. ALWAYS provide for efficiency." },
      limit: { type: "integer", description: "Max records to return. ALWAYS provide (e.g. 10 or 25) to avoid fetching all records." },
      aggregate: { type: "string", description: "Perform an aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on" },
      group_by_field: { type: "string", description: "Field to group results by, e.g. 'city', 'tag_list'" }
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
