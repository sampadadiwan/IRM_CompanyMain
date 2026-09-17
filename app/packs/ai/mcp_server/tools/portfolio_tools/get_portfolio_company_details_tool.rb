# frozen_string_literal: true

# MCP tool to get one portfolio company's details.
# Surface generated from the `portfolio_company` ontology.
# Delegates to {PortfolioAssistantDataManager#get_portfolio_company_details}.
class GetPortfolioCompanyDetailsTool < ApplicationMcpTool
  ontology "get_portfolio_company_details"

  def self.call(server_context:, portfolio_company_id:)
    json PortfolioAssistantDataManager.new(user: server_context[:user])
                                      .get_portfolio_company_details(portfolio_company_id: portfolio_company_id)
  end
end
