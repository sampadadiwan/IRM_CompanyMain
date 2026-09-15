# frozen_string_literal: true

# MCP tool to list portfolio company KPIs.
# Surface generated from the `kpi` ontology, whose scopes are compound (comma-separated).
# Delegates to {PortfolioAssistantDataManager#list_portfolio_kpis}.
class ListPortfolioKpisTool < ApplicationMcpTool
  ontology "list_portfolio_kpis"

  def self.call(server_context:, portfolio_company_ids: nil, scope: nil, query: {},
                sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    if (message = validation_error(query: query, sort: sort, scope: scope, aggregate: aggregate,
                                   aggregate_field: aggregate_field, group_by_field: group_by_field,
                                   portfolio_company_ids: portfolio_company_ids))
      return error(message)
    end

    json PortfolioAssistantDataManager.new(user: server_context[:user]).list_portfolio_kpis(
      portfolio_company_ids: portfolio_company_ids, scope: scope,
      query: ransack_query(query, aggregate_field: aggregate_field, group_by_field: group_by_field),
      sort: sort, limit: limit, aggregate: aggregate
    )
  end
end
