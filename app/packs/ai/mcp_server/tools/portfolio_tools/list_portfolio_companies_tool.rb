# frozen_string_literal: true

# MCP tool to list portfolio companies.
# Surface generated from the `portfolio_company` ontology.
# Delegates to {PortfolioAssistantDataManager#list_portfolio_companies}.
class ListPortfolioCompaniesTool < ApplicationMcpTool
  ontology "list_portfolio_companies"

  def self.call(server_context:, scope: nil, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    if (message = validation_error(query: query, sort: sort, scope: scope, aggregate: aggregate,
                                   aggregate_field: aggregate_field, group_by_field: group_by_field))
      return error(message)
    end

    json PortfolioAssistantDataManager.new(user: server_context[:user]).list_portfolio_companies(
      scope: scope,
      query: ransack_query(query, aggregate_field: aggregate_field, group_by_field: group_by_field),
      sort: sort, limit: limit, aggregate: aggregate
    )
  end
end
