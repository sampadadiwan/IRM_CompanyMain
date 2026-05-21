# frozen_string_literal: true

# MCP tool to list account entries (always aggregated — individual records cannot be fetched).
# Aggregation is mandatory per data manager contract.
# Delegates to {FundAssistantDataManager#list_account_entries}.
class ListAccountEntriesTool < ApplicationMcpTool
  description "List account entries (ALWAYS aggregated). This tool ONLY returns aggregated data (sum, count, group_by). " \
              "Individual records are never returned — aggregation is mandatory. " \
              "Attributes for filtering/grouping: name, entry_type, reporting_date, period, folio_id, amount, cumulative, generated, rule_for. " \
              "Use list_funds to find fund IDs, or list_capital_commitments to find folio IDs. " \
              "Ordering: Use `sort` for grouped results. Example: aggregate: 'group_by', group_by_field: 'entry_type', aggregate_field: 'amount', sort: 'total_cents desc'."

  input_schema(
    properties: {
      fund_ids: { type: "array", items: { type: "integer" }, description: "Filter by fund IDs. Use list_funds to find IDs by name." },
      folio_ids: { type: "array", items: { type: "string" }, description: "Filter by folio IDs. Use list_capital_commitments to find folio IDs." },
      scope: { type: "string", description: "Filter by a predefined scope: 'cumulative', 'not_cumulative', 'generated', 'fund_entries', 'reporting', 'accounting', 'for_folios', 'for_portfolio_investments', 'for_portfolio_companies'" },
      query: { type: "object", description: "Ransack query hash, e.g. { entry_type_eq: 'distribution', reporting_date_gteq: '2025-01-01' }" },
      sort: { type: "string", description: "Sort string for results, e.g. 'total_cents desc'." },
      limit: { type: "integer", description: "Max records to return for grouped results." },
      aggregate: { type: "string", description: "REQUIRED. Perform an aggregation: 'count', 'sum', or 'group_by'. Defaults to 'sum'." },
      aggregate_field: { type: "string", description: "Field to aggregate on. Defaults to 'amount'. Examples: 'amount'." },
      group_by_field: { type: "string", description: "Field to group results by, e.g. 'entry_type', 'name', 'period'" }
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
