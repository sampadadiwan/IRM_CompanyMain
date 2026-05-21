# frozen_string_literal: true

# MCP tool to list KPIs for portfolio companies with period and type filtering.
class ListPortfolioKpisTool < ApplicationMcpTool
  description "List KPIs for one or more portfolio companies. Returns KPI name, value, period, percentage change, " \
              "and as-of date. Supports filtering by company, period (monthly/quarterly/yearly), " \
              "type (actuals/budgets), and date range. Defaults to actuals for the last 12 months. " \
              "Construct a query hash using available attributes and predicates. " \
              "Attributes: name, value, source. " \
              "Predicates: _cont (contains), _eq (equals), _gt, _lt, _gteq (>=), _lteq (<=). " \
              "Use list_portfolio_companies first to find portfolio company IDs by name. " \
              "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'name asc', limit: 10."

  input_schema(
    properties: {
      portfolio_company_ids: {
        type: "array",
        items: { type: "integer" },
        description: "Filter by portfolio company IDs. Use list_portfolio_companies with { investor_name_cont: 'name' } to find IDs. If omitted, returns KPIs for all accessible companies."
      },
      scope: {
        type: "string",
        description: "Comma-separated scope filters: 'actuals', 'budgets', 'ics', 'monthly', 'quarterly', 'yearly', 'ytd'. " \
                     "Example: 'actuals,quarterly'. Defaults to 'actuals' if neither actuals nor budgets is specified."
      },
      query: {
        type: "object",
        description: "Ransack query hash, e.g. { name_cont: 'Revenue', kpi_report_as_of_gteq: '2025-01-01' }. " \
                     "Pass { all_time_eq: 'true' } to remove the default 12-month date filter."
      },
      sort: { type: "string", description: "Sort string, e.g. 'kpi_report_as_of desc', 'name asc'. ALWAYS provide for efficiency." },
      limit: { type: "integer", description: "Max records to return. ALWAYS provide (e.g. 10) to avoid fetching all records." },
      aggregate: { type: "string", description: "Perform an aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on, e.g. 'value'" },
      group_by_field: { type: "string", description: "Field to group results by, e.g. 'name'" }
    }
  )

  def self.call(server_context:, portfolio_company_ids: nil, scope: nil, query: {},
                sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    data_manager = PortfolioAssistantDataManager.new(user: server_context[:user])

    q = (query || {}).with_indifferent_access
    q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
    q[:group_by] ||= group_by_field if group_by_field.present?

    data = data_manager.list_portfolio_kpis(
      portfolio_company_ids: portfolio_company_ids,
      scope: scope, query: q, sort: sort,
      limit: limit, aggregate: aggregate
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
