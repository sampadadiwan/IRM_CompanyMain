# frozen_string_literal: true

# MCP tool to list account entries (always aggregated — individual records cannot be fetched).
# Aggregation is mandatory per data manager contract.
# Delegates to {FundAssistantDataManager#list_account_entries}.
class ListAccountEntriesTool < ApplicationMcpTool
  description "List account entries (ALWAYS aggregated). Only returns aggregated data (sum, count, group_by). " \
              "Individual records are never returned — aggregation is mandatory. " \
              "Attributes: name, entry_type, reporting_date, period, folio_id, amount, cumulative, generated, rule_for."

  input_schema(
    properties: {
      fund_ids: { type: "array", items: { type: "integer" }, description: "Filter by fund IDs" },
      folio_ids: { type: "array", items: { type: "string" }, description: "Filter by folio IDs" },
      scope: { type: "string", description: "Scope: 'cumulative', 'not_cumulative', 'generated', 'fund_entries', 'reporting', 'accounting', 'for_folios', 'for_portfolio_investments', 'for_portfolio_companies'" },
      query: { type: "object", description: "Ransack filter hash" },
      sort: { type: "string", description: "Sort string for grouped results" },
      limit: { type: "integer", description: "Limit number of results" },
      aggregate: { type: "string", description: "REQUIRED. Aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on. Defaults to 'amount'." },
      group_by_field: { type: "string", description: "Field to group results by" }
    },
    required: ["aggregate"]
  )

  def self.call(server_context:, aggregate:, fund_ids: nil, folio_ids: nil, scope: nil,
                query: {}, sort: nil, limit: nil, aggregate_field: nil, group_by_field: nil)
    data_manager = FundAssistantDataManager.new(user: server_context[:user])

    q = (query || {}).with_indifferent_access
    q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
    q[:group_by] ||= group_by_field if group_by_field.present?

    data = data_manager.list_account_entries(
      fund_ids: fund_ids, folio_ids: folio_ids, scope: scope,
      query: q, sort: sort, limit: limit, aggregate: aggregate
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
