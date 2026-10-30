# /method_length
class EsignUpdateJob < ApplicationJob
  # X9, X10: Zoho slow, down or rate limiting - check again later instead of failing the document.
  retry_on ZohoSignClient::TransientError, ZohoSignClient::RateLimited, wait: :polynomially_longer, attempts: 5 do |job, error|
    ErrorReport.notify(error, job:)
  end
  # Credentials refused: already reported (or the connection marked Needs reconnect); retrying can't help.
  discard_on ZohoSignClient::AuthError

  def perform(document_id, user_id)
    Chewy.strategy(:sidekiq) do
      # Find the document
      doc = Document.find(document_id)
      changed = EsignHelper.new(doc).update_esign_status

      message = if changed
                  "Document - #{doc.name}'s eSign status updated"
                else
                  "Document - #{doc.name}'s eSign status fetched - no changes"
                end
      UserAlert.new(message:, user_id:, level: "info").broadcast if user_id.present?
    end
  end
end
