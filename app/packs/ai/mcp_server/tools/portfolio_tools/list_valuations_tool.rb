# frozen_string_literal: true

# MCP tool to list valuations for a portfolio company.
class ListValuationsTool < ApplicationMcpTool
  description "List valuations for a portfolio company. Returns valuation date, per-share value, " \
              "currency, instrument, and synthetic flag. " \
              "Construct a query hash using available attributes and predicates. " \
              "Attributes: valuation_date, per_share_value_cents, currency, synthetic. " \
              "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
              "Use list_portfolio_companies first to find the portfolio_company_id by name. " \
              "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'top', 'latest', or 'largest' requests. Example: sort: 'valuation_date desc', limit: 10."

  input_schema(
    properties: {
      portfolio_company_id: { type: "integer", description: "The ID of the portfolio company. Use list_portfolio_companies with { investor_name_cont: 'name' } to find IDs." },
      scope: { type: "string", description: "Filter by a predefined scope: 'with_synthetic' to include synthetic valuations" },
      query: { type: "object", description: "Ransack query hash, e.g. { valuation_date_gteq: '2025-01-01', currency_eq: 'USD' }" },
      sort: { type: "string", description: "Sort string, e.g. 'valuation_date desc'. ALWAYS provide for efficiency." },
      limit: { type: "integer", description: "Max records to return. ALWAYS provide (e.g. 10) to avoid fetching all records." },
      aggregate: { type: "string", description: "Perform an aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on, e.g. 'per_share_value_cents'" },
      group_by_field: { type: "string", description: "Field to group results by, e.g. 'currency'" }
    },
    required: ["portfolio_company_id"]
  )

  def self.call(server_context:, portfolio_company_id:, scope: nil, query: {},
                sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    data_manager = PortfolioAssistantDataManager.new(user: server_context[:user])

    q = (query || {}).with_indifferent_access
    q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
    q[:group_by] ||= group_by_field if group_by_field.present?

    data = data_manager.list_valuations(
      portfolio_company_id: portfolio_company_id,
      scope: scope, query: q, sort: sort,
      limit: limit, aggregate: aggregate
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
