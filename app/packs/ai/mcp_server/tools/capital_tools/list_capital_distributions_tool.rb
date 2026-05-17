# frozen_string_literal: true

# MCP tool to list capital distributions with filtering, sorting, and aggregation.
# Delegates to {FundAssistantDataManager#list_capital_distributions}.
class ListCapitalDistributionsTool < ApplicationMcpTool
  description "List capital distributions with optional filtering, sorting, and aggregation. " \
              "Attributes: title, distribution_date, approved, completed, distribution_on, gross_amount, income, reinvestment. " \
              "Always pass sort and limit for efficiency."

  input_schema(
    properties: {
      fund_ids: { type: "array", items: { type: "integer" }, description: "Filter by fund IDs" },
      query: { type: "object", description: "Ransack filter hash, e.g. { distribution_date_gteq: '2024-01-01' }" },
      sort: { type: "string", description: "Sort string, e.g. 'distribution_date desc'" },
      limit: { type: "integer", description: "Limit number of results" },
      aggregate: { type: "string", description: "Aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on" },
      group_by_field: { type: "string", description: "Field to group results by" }
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
