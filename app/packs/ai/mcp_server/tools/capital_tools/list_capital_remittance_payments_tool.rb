# frozen_string_literal: true

# MCP tool to list capital remittance payments with filtering, sorting, and aggregation.
# Delegates to {FundAssistantDataManager#list_capital_remittance_payments}.
class ListCapitalRemittancePaymentsTool < ApplicationMcpTool
  description "List capital remittance payments (individual payment records for remittances). " \
              "Can be filtered by fund_ids, folio_ids, or a Ransack query. " \
              "Construct a query hash using available attributes and predicates. " \
              "Attributes: payment_date, reference_no, amount, folio_amount, tracking_amount. " \
              "Predicates: _cont (contains), _eq (equals), _gt, _lt, _gteq (>=), _lteq (<=). " \
              "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'payment_date desc', limit: 10."

  input_schema(
    properties: {
      fund_ids: { type: "array", items: { type: "integer" }, description: "Filter by fund IDs. Use list_funds to find IDs by name." },
      folio_ids: { type: "array", items: { type: "string" }, description: "Filter by folio IDs. Use list_capital_commitments to find folio IDs." },
      query: { type: "object", description: "Ransack query hash, e.g. { payment_date_gteq: '2024-01-01', reference_no_cont: 'REF' }" },
      sort: { type: "string", description: "Sort string, e.g. 'payment_date desc'. ALWAYS provide for efficiency." },
      limit: { type: "integer", description: "Max records to return. ALWAYS provide (e.g. 10) to avoid fetching all records." },
      aggregate: { type: "string", description: "Perform an aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on, e.g. 'amount'" },
      group_by_field: { type: "string", description: "Field to group results by, e.g. 'payment_date'" }
    }
  )

  def self.call(server_context:, fund_ids: nil, folio_ids: nil, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    data_manager = FundAssistantDataManager.new(user: server_context[:user])

    q = (query || {}).with_indifferent_access
    q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
    q[:group_by] ||= group_by_field if group_by_field.present?

    data = data_manager.list_capital_remittance_payments(
      fund_ids: fund_ids, folio_ids: folio_ids, query: q, sort: sort,
      limit: limit, aggregate: aggregate
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
