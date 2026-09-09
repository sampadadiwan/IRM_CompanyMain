# frozen_string_literal: true

# MCP tool for the line-by-line cap table across portfolio companies.
# Surface generated from the `investment` ontology.
# Delegates to {PortfolioAssistantDataManager#get_investments_in_cap_table}.
class GetInvestmentsInCapTableTool < ApplicationMcpTool
  ontology "get_investments_in_cap_table"

  def self.call(server_context:, portfolio_company_ids:, query: {}, sort: nil, limit: nil)
    if (message = validation_error(query: query, sort: sort, portfolio_company_ids: portfolio_company_ids))
      return error(message)
    end

    json PortfolioAssistantDataManager.new(user: server_context[:user]).get_investments_in_cap_table(
      portfolio_company_ids: portfolio_company_ids,
      query: ransack_query(query), sort: sort, limit: limit
    )
  end
end
