# frozen_string_literal: true

# MCP tool to list capital commitments (folios) with filtering, sorting, and aggregation.
# Delegates to {FundAssistantDataManager#list_capital_commitments}.
class ListCapitalCommitmentsTool < ApplicationMcpTool
  description "List capital commitments / Folios. Filter by fund_ids, folio_ids, or Ransack query. " \
              "If you need all commitments for a specific folio across funds, only provide folio_ids (no fund_ids). " \
              "Attributes: folio_id, commitment_date, fund_close, investor_name, onboarding_completed, " \
              "unit_type, committed_amount, collected_amount, call_amount, distribution_amount. " \
              "Always pass sort and limit for efficiency."

  input_schema(
    properties: {
      fund_ids: { type: "array", items: { type: "integer" }, description: "Filter by fund IDs" },
      folio_ids: { type: "array", items: { type: "string" }, description: "Filter by folio IDs" },
      scope: { type: "string", description: "Scope: 'lp_onboarding_complete' or 'lp_onboarding_incomplete'" },
      query: { type: "object", description: "Ransack filter hash, e.g. { investor_name_cont: 'Smith' }" },
      sort: { type: "string", description: "Sort string, e.g. 'committed_amount_cents desc'" },
      limit: { type: "integer", description: "Limit number of results" },
      aggregate: { type: "string", description: "Aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on" },
      group_by_field: { type: "string", description: "Field to group results by" }
    }
  )

  def self.call(server_context:, fund_ids: nil, folio_ids: nil, scope: nil, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    data_manager = FundAssistantDataManager.new(user: server_context[:user])

    q = (query || {}).with_indifferent_access
    q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
    q[:group_by] ||= group_by_field if group_by_field.present?

    data = data_manager.list_capital_commitments(
      fund_ids: fund_ids, folio_ids: folio_ids, scope: scope,
      query: q, sort: sort, limit: limit, aggregate: aggregate
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
