# frozen_string_literal: true

# MCP tool to list documents associated with a portfolio company.
# Delegates to {PortfolioAssistantDataManager#list_documents}.
class ListDocumentsTool < ApplicationMcpTool
  description "List documents associated with a portfolio company. " \
              "Attributes: name, owner_tag, text, public_visibility, esign_status. " \
              "Predicates: _cont, _eq, _gt, _lt, _gteq, _lteq. " \
              "Always pass sort and limit for efficiency."

  input_schema(
    properties: {
      portfolio_company_id: { type: "integer", description: "The ID of the portfolio company" },
      scope: { type: "string", description: "Scope: 'approved', 'not_approved', 'template', 'signed', 'esign_status_completed', etc." },
      query: { type: "object", description: "Ransack filter hash, e.g. { name_cont: 'Agreement' }" },
      sort: { type: "string", description: "Sort string, e.g. 'created_at desc'" },
      limit: { type: "integer", description: "Limit number of results" }
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
