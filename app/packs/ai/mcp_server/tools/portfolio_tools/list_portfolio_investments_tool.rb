# frozen_string_literal: true

# MCP tool to list portfolio investments (buys, sells, conversions) for a company.
class ListPortfolioInvestmentsTool < ApplicationMcpTool
  description "List portfolio investments for a company. Returns fund, instrument, dates, amounts, " \
              "quantities, FMV, gains, and proforma status. Filter by transaction type using scope: " \
              "'buys', 'sells', 'conversions', 'distributed', 'not_distributed', 'proforma', 'non_proforma'."

  input_schema(
    properties: {
      portfolio_company_id: { type: "integer", description: "The ID of the portfolio company" },
      scope: {
        type: "string",
        description: "Filter by transaction type: 'buys', 'sells', 'conversions', 'distributed', " \
                     "'not_distributed', 'proforma', 'non_proforma'"
      },
      query: { type: "object", description: "Ransack filter hash, e.g. { investment_date_gteq: '2025-01-01' }" },
      sort: { type: "string", description: "Sort string, e.g. 'investment_date desc'" },
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

    data = data_manager.list_portfolio_investments(
      portfolio_company_id: portfolio_company_id,
      scope: scope, query: q, sort: sort,
      limit: limit, aggregate: aggregate
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
