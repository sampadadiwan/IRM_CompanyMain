# frozen_string_literal: true

# MCP tool to list investments in the cap table across portfolio companies.
class GetInvestmentsInCapTableTool < ApplicationMcpTool
  description "Get detailed list of investments in cap table for one or more portfolio companies. " \
              "Construct a query hash using available attributes and predicates. " \
              "Attributes: investor_name, category, investment_type, funding_round, investment_date, quantity, amount_cents. " \
              "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
              "Use get_cap_table for an aggregated shareholding view instead. " \
              "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Examples: sort: 'investment_date desc', limit: 10."

  input_schema(
    properties: {
      portfolio_company_ids: {
        type: "array",
        items: { type: "integer" },
        description: "List of portfolio company IDs. Use list_portfolio_companies with { investor_name_cont: 'name' } to find IDs."
      },
      query: { type: "object", description: "Ransack query hash, e.g. { funding_round_eq: 'Series A', investor_name_cont: 'Smith' }" },
      sort: { type: "string", description: "Sort string, e.g. 'investment_date desc'. ALWAYS provide for efficiency." },
      limit: { type: "integer", description: "Max records to return. ALWAYS provide (e.g. 10) to avoid fetching all records." }
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
