# frozen_string_literal: true

# MCP tool for a portfolio company's executive summary — invested, FMV, latest valuation and
# return multiples. Surface generated from the `portfolio_company` ontology.
# Delegates to {PortfolioAssistantDataManager#get_portfolio_company_snapshot}.
class GetPortfolioCompanySnapshotTool < ApplicationMcpTool
  ontology "get_portfolio_company_snapshot"

  def self.call(server_context:, portfolio_company_id:)
    json PortfolioAssistantDataManager.new(user: server_context[:user])
                                      .get_portfolio_company_snapshot(portfolio_company_id: portfolio_company_id)
  end
end
