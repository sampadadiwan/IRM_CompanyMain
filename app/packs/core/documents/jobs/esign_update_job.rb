# /method_length
class EsignUpdateJob < ApplicationJob
  def perform(document_id, user_id)
    Chewy.strategy(:active_job) do
      # Find the document
      doc = Document.find(document_id)
      DigioEsignHelper.new.update_esign_status(doc)

      message = "Document - #{doc.name}'s E-Sign status updated"
      UserAlert.new(message:, user_id:, level: "info").broadcast if user_id.present?
    end
  end
end
