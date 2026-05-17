# frozen_string_literal: true

# MCP tool to list valuations for a portfolio company.
class ListValuationsTool < ApplicationMcpTool
  description "List valuations for a portfolio company. Returns valuation date, per-share value, " \
              "currency, instrument, and synthetic flag. Use sort 'valuation_date desc' for latest first."

  input_schema(
    properties: {
      portfolio_company_id: { type: "integer", description: "The ID of the portfolio company" },
      scope: { type: "string", description: "Scope filter, e.g. 'with_synthetic' to include synthetic valuations" },
      query: { type: "object", description: "Ransack filter hash, e.g. { valuation_date_gteq: '2025-01-01', currency_eq: 'USD' }" },
      sort: { type: "string", description: "Sort string, e.g. 'valuation_date desc'" },
      limit: { type: "integer", description: "Limit number of results" },
      aggregate: { type: "string", description: "Aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on" },
      group_by_field: { type: "string", description: "Field to group results by" }
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
