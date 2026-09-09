# frozen_string_literal: true

# MCP tool to list a portfolio company's valuations.
# Surface generated from the `valuation` ontology.
# Delegates to {PortfolioAssistantDataManager#list_valuations}.
class ListValuationsTool < ApplicationMcpTool
  ontology "list_valuations"

  def self.call(server_context:, portfolio_company_id: nil, scope: nil, query: {},
                sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    if (message = validation_error(query: query, sort: sort, scope: scope, aggregate: aggregate,
                                   aggregate_field: aggregate_field, group_by_field: group_by_field,
                                   portfolio_company_id: portfolio_company_id))
      return error(message)
    end

    json PortfolioAssistantDataManager.new(user: server_context[:user]).list_valuations(
      portfolio_company_id: portfolio_company_id, scope: scope,
      query: ransack_query(query, aggregate_field: aggregate_field, group_by_field: group_by_field),
      sort: sort, limit: limit, aggregate: aggregate
    )
  end
end
