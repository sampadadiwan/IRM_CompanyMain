# frozen_string_literal: true

# MCP tool to aggregate account entries. Individual rows are never returned — the ledger is
# the largest table in the system. Surface generated from the `account_entry` ontology.
# Delegates to {FundAssistantDataManager#list_account_entries}.
class ListAccountEntriesTool < ApplicationMcpTool
  ontology "list_account_entries"

  def self.call(server_context:, aggregate:, fund_ids: nil, folio_ids: nil, scope: nil,
                query: {}, sort: nil, limit: nil, aggregate_field: nil, group_by_field: nil)
    if (message = validation_error(query: query, sort: sort, scope: scope, aggregate: aggregate,
                                   aggregate_field: aggregate_field, group_by_field: group_by_field,
                                   fund_ids: fund_ids, folio_ids: folio_ids))
      return error(message)
    end

    json FundAssistantDataManager.new(user: server_context[:user]).list_account_entries(
      fund_ids: fund_ids, folio_ids: folio_ids, scope: scope,
      query: ransack_query(query, aggregate_field: aggregate_field, group_by_field: group_by_field),
      sort: sort, limit: limit, aggregate: aggregate
    )
  end
end
