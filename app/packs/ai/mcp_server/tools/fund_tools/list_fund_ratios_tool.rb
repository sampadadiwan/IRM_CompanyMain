# frozen_string_literal: true

# MCP tool to list fund performance ratios. Surface generated from the `fund_ratio` ontology.
# Delegates to {FundAssistantDataManager#list_fund_ratios}.
class ListFundRatiosTool < ApplicationMcpTool
  ontology "list_fund_ratios"

  def self.call(server_context:, fund_ids: nil, scope: nil, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    if (message = validation_error(query: query, sort: sort, scope: scope, aggregate: aggregate,
                                   aggregate_field: aggregate_field, group_by_field: group_by_field,
                                   fund_ids: fund_ids))
      return error(message)
    end

    json FundAssistantDataManager.new(user: server_context[:user]).list_fund_ratios(
      fund_ids: fund_ids, scope: scope,
      query: ransack_query(query, aggregate_field: aggregate_field, group_by_field: group_by_field),
      sort: sort, limit: limit, aggregate: aggregate
    )
  end
end
