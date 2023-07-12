# Updates the status of the e-signing process for a document
# Calls EsignUpdateJob for each document
class DocumentEsignUpdateJob < ApplicationJob
  queue_as :low

  # This is called every day at 2:01 am for all docs created in the last 10 days
  # to update the status of the e-signing process
  # Or it can be called with a document_id to update a single document
  def perform(document_id)
    Chewy.strategy(:sidekiq) do
      docs = Document.where('created_at > ?', 10.days.ago.beginning_of_day).sent_for_esign
      docs = Document.where(id: [document_id]) if document_id.present?
      docs.each do |doc|
        # .where.not query skips nil esign statuses
        EsignUpdateJob.perform_later(doc.id) unless Document::SKIP_ESIGN_UPDATE_STATUSES.include?(doc.esign_status)
      end
    end
  end
end
