# frozen_string_literal: true

# MCP tool to list payments received against capital remittances.
# Surface generated from the `capital_remittance_payment` ontology.
# Delegates to {FundAssistantDataManager#list_capital_remittance_payments}.
class ListCapitalRemittancePaymentsTool < ApplicationMcpTool
  ontology "list_capital_remittance_payments"

  def self.call(server_context:, fund_ids: nil, folio_ids: nil, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    if (message = validation_error(query: query, sort: sort, aggregate: aggregate,
                                   aggregate_field: aggregate_field, group_by_field: group_by_field,
                                   fund_ids: fund_ids, folio_ids: folio_ids))
      return error(message)
    end

    json FundAssistantDataManager.new(user: server_context[:user]).list_capital_remittance_payments(
      fund_ids: fund_ids, folio_ids: folio_ids,
      query: ransack_query(query, aggregate_field: aggregate_field, group_by_field: group_by_field),
      sort: sort, limit: limit, aggregate: aggregate
    )
  end
end
