# frozen_string_literal: true

# MCP tool to list capital calls with filtering, sorting, and aggregation.
# Delegates to {FundAssistantDataManager#list_capital_calls}.
class ListCapitalCallsTool < ApplicationMcpTool
  description "List capital calls with optional Ransack filtering, ordering, and limiting. " \
              "Construct a query hash using available attributes and predicates. " \
              "Attributes: name, due_date, approved, call_date, status, verified, call_amount, collected_amount, percentage_called. " \
              "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
              "Use list_funds first to find fund IDs, then filter calls by fund_ids. " \
              "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'top', 'latest', or 'largest' requests. Example: sort: 'due_date desc', limit: 5."

  input_schema(
    properties: {
      fund_ids: { type: "array", items: { type: "integer" }, description: "Filter by fund IDs. Use list_funds to find IDs by name." },
      query: { type: "object", description: "Ransack query hash, e.g. { due_date_gteq: '2024-01-01', status_eq: 'active' }. Combine attribute + predicate." },
      sort: { type: "string", description: "Sort string, e.g. 'due_date desc', 'call_amount_cents desc'. Maps to Ransack `s`. ALWAYS provide for efficiency." },
      limit: { type: "integer", description: "Max records to return. ALWAYS provide (e.g. 5 or 10) to avoid fetching all records." },
      aggregate: { type: "string", description: "Perform an aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on, e.g. 'call_amount', 'collected_amount'" },
      group_by_field: { type: "string", description: "Field to group results by, e.g. 'status'" }
    }
  )

  def self.call(server_context:, fund_ids: nil, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    data_manager = FundAssistantDataManager.new(user: server_context[:user])

    q = (query || {}).with_indifferent_access
    q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
    q[:group_by] ||= group_by_field if group_by_field.present?

    data = data_manager.list_capital_calls(
      fund_ids: fund_ids, query: q, sort: sort,
      limit: limit, aggregate: aggregate
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
