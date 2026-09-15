# frozen_string_literal: true

# MCP tool to list documents filed against a portfolio company.
# Surface generated from the `document` ontology.
# Delegates to {PortfolioAssistantDataManager#list_documents}.
class ListDocumentsTool < ApplicationMcpTool
  ontology "list_documents"

  def self.call(server_context:, portfolio_company_id: nil, scope: nil, query: {}, sort: nil, limit: nil)
    if (message = validation_error(query: query, sort: sort, scope: scope,
                                   portfolio_company_id: portfolio_company_id))
      return error(message)
    end

    json PortfolioAssistantDataManager.new(user: server_context[:user]).list_documents(
      portfolio_company_id: portfolio_company_id, scope: scope,
      query: ransack_query(query), sort: sort, limit: limit
    )
  end
end
