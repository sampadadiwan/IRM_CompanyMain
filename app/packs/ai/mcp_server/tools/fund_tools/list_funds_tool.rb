# frozen_string_literal: true

# MCP tool to list funds with committed, collected and distribution amounts.
# Delegates to {FundAssistantDataManager#list_funds} with Ransack filtering, sorting, and aggregation.
class ListFundsTool < ApplicationMcpTool
  description "List all funds with committed, collected and distribution amounts. " \
              "Supports filtering, sorting, and aggregation. " \
              "Attributes: name, currency, tracking_currency, category, tag_list, unit_types, first_close_date, last_close_date, start_date. " \
              "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
              "Hint: For totals, use the funds data directly; do not compute using commitments, remittances or distributions."

  input_schema(
    properties: {
      scope: { type: "string", description: "Filter: 'feeder_funds' or 'master_funds'" },
      query: { type: "object", description: "Ransack filter hash, e.g. { name_cont: 'Venture', currency_eq: 'USD' }" },
      sort: { type: "string", description: "Sort string, e.g. 'name asc', 'committed_amount_cents desc'" },
      limit: { type: "integer", description: "Limit number of results" },
      aggregate: { type: "string", description: "Aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on" },
      group_by_field: { type: "string", description: "Field to group results by" }
    }
  )

  def self.call(server_context:, scope: nil, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    data_manager = FundAssistantDataManager.new(user: server_context[:user])

    q = (query || {}).with_indifferent_access
    q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
    q[:group_by] ||= group_by_field if group_by_field.present?

    data = data_manager.list_funds(
      scope: scope, query: q, sort: sort,
      limit: limit, aggregate: aggregate
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
