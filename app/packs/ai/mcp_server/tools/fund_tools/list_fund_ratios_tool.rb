# frozen_string_literal: true

# MCP tool to list fund ratios (performance metrics like TVPI, IRR, DPI, etc.).
# Delegates to {FundAssistantDataManager#list_fund_ratios}.
class ListFundRatiosTool < ApplicationMcpTool
  description "List fund ratios and performance metrics (e.g. TVPI, IRR, DPI, RVPI). " \
              "Supports filtering by fund_ids, Ransack query, sorting, and aggregation. " \
              "Attributes: name, value, owner_type, owner_id, end_date, latest."

  input_schema(
    properties: {
      fund_ids: { type: "array", items: { type: "integer" }, description: "Filter by fund IDs" },
      query: { type: "object", description: "Ransack filter hash, e.g. { name_eq: 'TVPI', latest_eq: true }" },
      sort: { type: "string", description: "Sort string, e.g. 'end_date desc'" },
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

    data = data_manager.list_fund_ratios(
      fund_ids: fund_ids, query: q, sort: sort,
      limit: limit, aggregate: aggregate
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
