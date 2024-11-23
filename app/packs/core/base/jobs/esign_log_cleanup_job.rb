class EsignLogCleanupJob < ApplicationJob
  def perform
    EsignLog.where(created_at: ...91.days.ago).destroy_all
    Document.where(esign_status: "completed").find_each do |doc|
      next if doc.esign_log.blank?

      # for documents where esign is completed, the logs will be deleted after 10 days
      doc.esign_log.destroy if doc.esign_log.updated_at < 10.days.ago
    end
  end
end
