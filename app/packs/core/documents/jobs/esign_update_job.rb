# /method_length
class EsignUpdateJob < ApplicationJob
  def perform(document_id, user_id)
    Chewy.strategy(:sidekiq) do
      # Find the document
      doc = Document.find(document_id)
      EsignHelper.new(doc).update_esign_status

      message = "Document - #{doc.name}'s eSign status updated"
      UserAlert.new(message:, user_id:, level: "info").broadcast if user_id.present?
    end
  end
end
