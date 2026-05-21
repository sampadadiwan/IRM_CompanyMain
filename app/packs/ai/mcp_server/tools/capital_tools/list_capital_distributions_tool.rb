# frozen_string_literal: true

# MCP tool to list capital distributions with filtering, sorting, and aggregation.
# Delegates to {FundAssistantDataManager#list_capital_distributions}.
class ListCapitalDistributionsTool < ApplicationMcpTool
  description "List capital distributions with optional Ransack filtering, ordering, and limiting. " \
              "Construct a query hash using available attributes and predicates. " \
              "Attributes: title, distribution_date, approved, completed, distribution_on, gross_amount, income, reinvestment. " \
              "Predicates: _cont (contains), _eq (equals), _gt, _lt, _gteq (>=), _lteq (<=). " \
              "Use list_funds first to find fund IDs, then filter distributions by fund_ids. " \
              "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'latest' or 'largest' requests. Example: sort: 'distribution_date desc', limit: 5."

  input_schema(
    properties: {
      fund_ids: { type: "array", items: { type: "integer" }, description: "Filter by fund IDs. Use list_funds to find IDs by name." },
      query: { type: "object", description: "Ransack query hash, e.g. { distribution_date_gteq: '2024-01-01', approved_eq: true }" },
      sort: { type: "string", description: "Sort string, e.g. 'distribution_date desc', 'gross_amount_cents desc'. ALWAYS provide for efficiency." },
      limit: { type: "integer", description: "Max records to return. ALWAYS provide (e.g. 5 or 10) to avoid fetching all records." },
      aggregate: { type: "string", description: "Perform an aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on, e.g. 'gross_amount', 'income', 'reinvestment'" },
      group_by_field: { type: "string", description: "Field to group results by, e.g. 'title', 'approved'" }
    }
  )

  def self.call(server_context:, fund_ids: nil, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    data_manager = FundAssistantDataManager.new(user: server_context[:user])

    q = (query || {}).with_indifferent_access
    q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
    q[:group_by] ||= group_by_field if group_by_field.present?

    data = data_manager.list_capital_distributions(
      fund_ids: fund_ids, query: q, sort: sort,
      limit: limit, aggregate: aggregate
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
