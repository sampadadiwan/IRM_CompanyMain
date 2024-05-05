# Updates the status of the e-signing process for a document
# Calls EsignUpdateJob for each document
class DocumentEsignUpdateJob < ApplicationJob
  queue_as :low

  # This is called every day at 2:01 am for all docs created in the last 10 days
  # to update the status of the e-signing process
  # Or it can be called with a document_id to update a single document
  def perform(document_id, user_id)
    Chewy.strategy(:active_job) do
      docs = Document.where('created_at > ?', 10.days.ago.beginning_of_day).sent_for_esign
      docs = Document.where(id: [document_id]) if document_id.present?
      docs.each do |doc|
        if Document::SKIP_ESIGN_UPDATE_STATUSES.exclude?(doc.esign_status)
          EsignUpdateJob.perform_later(doc.id, user_id)
        else
          message = "Document - #{doc.name}'s E-Sign status update Skipped"
          # only showing user alert if a single document is getting updated
          UserAlert.new(message:, user_id:, level: "warning").broadcast if user_id.present? && document_id.present?
        end
      end
    end
  end
end
