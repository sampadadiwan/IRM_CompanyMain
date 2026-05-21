# frozen_string_literal: true

# MCP tool to generate a cap table for a portfolio company.
class GetCapTableTool < ApplicationMcpTool
  description "Generate a capitalization table for a portfolio company. Returns shareholding data " \
              "grouped by investor name (default), funding round, or category. " \
              "Optionally filter by specific funding rounds. " \
              "Use list_portfolio_companies first to find the portfolio_company_id by name. " \
              "For detailed individual investments, use get_investments_in_cap_table instead."

  input_schema(
    properties: {
      portfolio_company_id: { type: "integer", description: "The ID of the portfolio company. Use list_portfolio_companies with { investor_name_cont: 'name' } to find IDs." },
      funding_rounds: {
        type: "array",
        items: { type: "string" },
        description: "Filter by specific funding rounds, e.g. ['Series A', 'Series B']. If omitted, includes all rounds."
      },
      group_by_field: {
        type: "string",
        description: "Field to group the cap table by: 'investor_name' (default), 'funding_round', or 'category'"
      }
    },
    required: ["portfolio_company_id"]
  )

  def self.call(server_context:, portfolio_company_id:, funding_rounds: nil, group_by_field: :investor_name)
    data_manager = PortfolioAssistantDataManager.new(user: server_context[:user])
    data = data_manager.get_cap_table(
      portfolio_company_id: portfolio_company_id,
      funding_rounds: funding_rounds,
      group_by_field: group_by_field
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
