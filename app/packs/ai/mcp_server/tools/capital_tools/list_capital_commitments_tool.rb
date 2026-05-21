# frozen_string_literal: true

# MCP tool to list capital commitments (folios) with filtering, sorting, and aggregation.
# Delegates to {FundAssistantDataManager#list_capital_commitments}.
class ListCapitalCommitmentsTool < ApplicationMcpTool
  description "List capital commitments / Folios. Can be filtered by fund_ids, folio_ids, or a Ransack query. " \
              "IMPORTANT: If you need all commitments for a specific folio across all funds, ONLY provide folio_ids (no fund_ids). " \
              "CRITICAL: If you find yourself calling this tool repeatedly with different fund IDs for the same folio, STOP. Call once with folio_ids and NO fund_ids to get all data in one go. " \
              "Attributes: folio_id, commitment_date, fund_close, investor_name, onboarding_completed, " \
              "unit_type, committed_amount, collected_amount, call_amount, distribution_amount. " \
              "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'top', 'largest', or 'most recent' requests. Example: sort: 'committed_amount_cents desc', limit: 10."

  input_schema(
    properties: {
      fund_ids: { type: "array", items: { type: "integer" }, description: "Filter by fund IDs. Use list_funds to find IDs. Do NOT provide if using folio_ids across all funds." },
      folio_ids: { type: "array", items: { type: "string" }, description: "Filter by folio IDs. Provide ONLY folio_ids (no fund_ids) to get all commitments for a folio across funds." },
      scope: { type: "string", description: "Filter by a predefined scope: 'lp_onboarding_complete' or 'lp_onboarding_incomplete'" },
      query: { type: "object", description: "Ransack query hash, e.g. { investor_name_cont: 'Smith', committed_amount_cents_gt: 100000 }" },
      sort: { type: "string", description: "Sort string, e.g. 'committed_amount_cents desc', 'commitment_date desc'. ALWAYS provide for efficiency." },
      limit: { type: "integer", description: "Max records to return. ALWAYS provide (e.g. 10 or 25) to avoid fetching all records." },
      aggregate: { type: "string", description: "Perform an aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on, e.g. 'committed_amount', 'collected_amount', 'call_amount', 'distribution_amount'" },
      group_by_field: { type: "string", description: "Field to group results by, e.g. 'investor_name', 'unit_type'" }
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
