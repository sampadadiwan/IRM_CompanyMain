# frozen_string_literal: true

# MCP tool to list investments in the cap table across portfolio companies.
class GetInvestmentsInCapTableTool < ApplicationMcpTool
  description "List investments in the cap table across one or more portfolio companies. " \
              "Returns investor name, investment type, funding round, currency, price, date, amount, " \
              "and quantity. Use get_cap_table for an aggregated view instead."

  input_schema(
    properties: {
      portfolio_company_ids: {
        type: "array",
        items: { type: "integer" },
        description: "List of portfolio company IDs to query"
      },
      query: { type: "object", description: "Ransack filter hash, e.g. { funding_round_eq: 'Series A' }" },
      sort: { type: "string", description: "Sort string, e.g. 'investment_date desc'" },
      limit: { type: "integer", description: "Limit number of results" }
    },
    required: ["portfolio_company_ids"]
  )

  def self.call(server_context:, portfolio_company_ids:, query: {}, sort: nil, limit: nil)
    data_manager = PortfolioAssistantDataManager.new(user: server_context[:user])
    data = data_manager.get_investments_in_cap_table(
      portfolio_company_ids: portfolio_company_ids,
      query: (query || {}).with_indifferent_access,
      sort: sort,
      limit: limit
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
