# frozen_string_literal: true

# MCP tool to get one document's metadata and file URL by ID or name.
# Surface generated from the `document` ontology.
# Delegates to {PortfolioAssistantDataManager#get_document}.
class GetDocumentTool < ApplicationMcpTool
  ontology "get_document"

  def self.call(server_context:, document_id: nil, name: nil)
    return error("Provide either document_id or name.") if document_id.blank? && name.blank?

    json PortfolioAssistantDataManager.new(user: server_context[:user])
                                      .get_document(document_id: document_id, name: name)
  end
end
