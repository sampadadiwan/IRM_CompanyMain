# frozen_string_literal: true

# MCP tool to list capital remittances (per-investor shares of a capital call).
# Surface generated from the `capital_remittance` ontology, which also declares the
# at-least-one-filter guard enforced by ApplicationMcpTool.
# Delegates to {FundAssistantDataManager#list_capital_remittances}.
class ListCapitalRemittancesTool < ApplicationMcpTool
  ontology "list_capital_remittances"

  def self.call(server_context:, fund_ids: nil, folio_ids: nil, scope: nil, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    if (message = validation_error(query: query, sort: sort, scope: scope, aggregate: aggregate,
                                   aggregate_field: aggregate_field, group_by_field: group_by_field,
                                   fund_ids: fund_ids, folio_ids: folio_ids))
      return error(message)
    end

    json FundAssistantDataManager.new(user: server_context[:user]).list_capital_remittances(
      fund_ids: fund_ids, folio_ids: folio_ids, scope: scope,
      query: ransack_query(query, aggregate_field: aggregate_field, group_by_field: group_by_field),
      sort: sort, limit: limit, aggregate: aggregate
    )
  end
end
