# frozen_string_literal: true

# MCP tool to get detailed information about a specific document by ID or name.
# Supports partial name matching. Delegates to {PortfolioAssistantDataManager#get_document}.
class GetDocumentTool < ApplicationMcpTool
  description "Get detailed information and full text content for a specific document by ID or name. " \
              "Returns document metadata, folder path, tags, e-sign status, and download URL. " \
              "Provide either document_id or name (partial match supported). " \
              "Use list_documents first to find document IDs for a portfolio company."

  input_schema(
    properties: {
      document_id: { type: "integer", description: "The ID of the document. Use list_documents to find IDs." },
      name: { type: "string", description: "The name of the document (partial match supported, e.g. 'Agreement' matches 'Subscription Agreement')" }
    }
  )

  def self.call(server_context:, document_id: nil, name: nil)
    data_manager = PortfolioAssistantDataManager.new(user: server_context[:user])
    data = data_manager.get_document(document_id: document_id, name: name)

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
