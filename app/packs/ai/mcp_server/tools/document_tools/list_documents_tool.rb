# frozen_string_literal: true

# MCP tool to list documents associated with a portfolio company.
# Delegates to {PortfolioAssistantDataManager#list_documents}.
class ListDocumentsTool < ApplicationMcpTool
  description "List documents associated with a portfolio company. " \
              "Construct a query hash using available attributes and predicates. " \
              "Attributes: name, owner_tag, text, public_visibility, esign_status. " \
              "Predicates: _cont (contains), _eq (equals), _gt (greater than), _lt (less than), _gteq (>=), _lteq (<=). " \
              "Use list_portfolio_companies first to find the portfolio_company_id by name. " \
              "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'top', 'latest', or 'largest' requests. Example: sort: 'created_at desc', limit: 10."

  input_schema(
    properties: {
      portfolio_company_id: { type: "integer", description: "The ID of the portfolio company. Use list_portfolio_companies with { investor_name_cont: 'name' } to find IDs." },
      scope: { type: "string", description: "Filter by a predefined scope: 'approved', 'not_approved', 'template', 'not_template', 'sent_for_esign', 'not_sent_for_esign', 'signed', 'esign_status_completed', 'esign_status_failed', 'esign_status_requested'" },
      query: { type: "object", description: "Ransack query hash, e.g. { name_cont: 'Agreement', esign_status_eq: 'completed' }" },
      sort: { type: "string", description: "Sort string, e.g. 'created_at desc'. ALWAYS provide for efficiency." },
      limit: { type: "integer", description: "Max records to return. ALWAYS provide (e.g. 10) to avoid fetching all records." }
    },
    required: ["portfolio_company_id"]
  )

  def self.call(server_context:, portfolio_company_id:, scope: nil, query: {}, sort: nil, limit: nil)
    data_manager = PortfolioAssistantDataManager.new(user: server_context[:user])

    data = data_manager.list_documents(
      portfolio_company_id: portfolio_company_id,
      scope: scope, query: query || {}, sort: sort, limit: limit
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
