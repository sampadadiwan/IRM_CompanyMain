# frozen_string_literal: true

# MCP tool for a portfolio company's aggregated cap table.
# Surface generated from the `investment` ontology.
# Delegates to {PortfolioAssistantDataManager#get_cap_table}.
class GetCapTableTool < ApplicationMcpTool
  ontology "get_cap_table"

  def self.call(server_context:, portfolio_company_id:, funding_rounds: nil, group_by_field: :investor_name)
    json PortfolioAssistantDataManager.new(user: server_context[:user]).get_cap_table(
      portfolio_company_id: portfolio_company_id,
      funding_rounds: funding_rounds,
      group_by_field: group_by_field
    )
  end
end
