# frozen_string_literal: true

# MCP tool to list capital remittances with filtering, sorting, and aggregation.
# Enforces at least one filter to prevent unbounded queries on large datasets.
# Delegates to {FundAssistantDataManager#list_capital_remittances}.
class ListCapitalRemittancesTool < ApplicationMcpTool
  description "List capital remittances (investor payments toward capital calls). " \
              "REQUIRED: At least one filter (fund_ids, folio_ids, scope, or query) must be provided — unfiltered queries are rejected. " \
              "Construct a query hash using available attributes and predicates. " \
              "Attributes: folio_id, investor_name, payment_date, remittance_date, call_amount, collected_amount. " \
              "Predicates: _cont (contains), _eq (equals), _gt, _lt, _gteq (>=), _lteq (<=). " \
              "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'latest', 'largest', or 'top' requests. Example: sort: 'payment_date desc', limit: 10."

  input_schema(
    properties: {
      fund_ids: { type: "array", items: { type: "integer" }, description: "Filter by fund IDs. Use list_funds to find IDs by name." },
      folio_ids: { type: "array", items: { type: "string" }, description: "Filter by folio IDs. Use list_capital_commitments to find folio IDs." },
      scope: { type: "string", description: "Filter by a predefined scope: 'paid', 'pending', 'verified', or 'unverified'" },
      query: { type: "object", description: "Ransack query hash, e.g. { investor_name_cont: 'Smith', payment_date_gteq: '2024-01-01' }" },
      sort: { type: "string", description: "Sort string, e.g. 'payment_date desc'. ALWAYS provide for efficiency." },
      limit: { type: "integer", description: "Max records to return. ALWAYS provide (e.g. 10) to avoid fetching all records." },
      aggregate: { type: "string", description: "Perform an aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on, e.g. 'call_amount', 'collected_amount'" },
      group_by_field: { type: "string", description: "Field to group results by, e.g. 'investor_name', 'folio_id'" }
    }
  )

  def self.call(server_context:, fund_ids: nil, folio_ids: nil, scope: nil, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    if fund_ids.blank? && folio_ids.blank? && scope.blank? &&
       (query.blank? || query.values.all?(&:blank?)) && aggregate.blank?
      return MCP::Tool::Response.new([{
                                       type: "text",
                                       text: { error: "At least one filter (fund_ids, folio_ids, scope, or query) or aggregate must be provided." }.to_json
                                     }])
    end

    data_manager = FundAssistantDataManager.new(user: server_context[:user])

    q = (query || {}).with_indifferent_access
    q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
    q[:group_by] ||= group_by_field if group_by_field.present?

    data = data_manager.list_capital_remittances(
      fund_ids: fund_ids, folio_ids: folio_ids, scope: scope,
      query: q, sort: sort, limit: limit, aggregate: aggregate
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
