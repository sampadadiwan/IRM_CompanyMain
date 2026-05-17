# frozen_string_literal: true

# MCP tool to list capital distribution payments with filtering, sorting, and aggregation.
# Enforces at least one filter to prevent unbounded queries on large datasets.
# Delegates to {FundAssistantDataManager#list_capital_distribution_payments}.
class ListCapitalDistributionPaymentsTool < ApplicationMcpTool
  description "List capital distribution payments. At least one filter (fund_ids, folio_ids, or scope) must be provided. " \
              "Always pass sort and limit for efficiency."

  input_schema(
    properties: {
      fund_ids: { type: "array", items: { type: "integer" }, description: "Filter by fund IDs" },
      folio_ids: { type: "array", items: { type: "string" }, description: "Filter by folio IDs" },
      scope: { type: "string", description: "Scope: 'completed', 'incomplete', 'notification_sent', or 'notification_not_sent'" },
      sort: { type: "string", description: "Sort string, e.g. 'payment_date desc'" },
      limit: { type: "integer", description: "Limit number of results" },
      aggregate: { type: "string", description: "Aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on" },
      group_by_field: { type: "string", description: "Field to group results by" }
    }
  )

  def self.call(server_context:, fund_ids: nil, folio_ids: nil, scope: nil, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    if fund_ids.blank? && folio_ids.blank? && scope.blank? && aggregate.blank?
      return MCP::Tool::Response.new([{
                                       type: "text",
                                       text: { error: "At least one filter (fund_ids, folio_ids, or scope) or aggregate must be provided." }.to_json
                                     }])
    end

    data_manager = FundAssistantDataManager.new(user: server_context[:user])

    query = { aggregate_field: aggregate_field, group_by: group_by_field }.compact

    data = data_manager.list_capital_distribution_payments(
      fund_ids: fund_ids, folio_ids: folio_ids, scope: scope,
      sort: sort, limit: limit, aggregate: aggregate, query: query
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
