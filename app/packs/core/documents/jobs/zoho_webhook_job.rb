# Applies a Zoho Sign webhook that the controller has already verified and acknowledged.
# connection_id is nil for CapHive's shared address (DocumentsController#signature_progress).
class ZohoWebhookJob < ApplicationJob
  queue_as :default

  # Zoho slow, down or rate limiting while downloading the signed copy - try again later.
  retry_on ZohoSignClient::TransientError, ZohoSignClient::RateLimited, wait: :polynomially_longer, attempts: 5 do |job, error|
    ErrorReport.notify(error, job:)
  end
  # Credentials refused: already reported; retrying can't help.
  discard_on ZohoSignClient::AuthError, ActiveRecord::RecordNotFound

  def perform(connection_id, raw_body)
    payload = JSON.parse(raw_body)
    request_id = payload.dig("requests", "request_id")
    doc = find_document(connection_id, request_id)
    # E32: a request we don't track (or not in this address's scope) is acknowledged and ignored
    return Rails.logger.info("Zoho Sign webhook for request #{request_id} ignored - no matching document") if doc.nil?

    Chewy.strategy(:sidekiq) do
      ZohoEsignHelper.new.update_signature_progress(doc, payload)
    end
  rescue JSON::ParserError => e
    Rails.logger.warn("Zoho Sign webhook body is not JSON - #{e.message}")
  end

  private

  # The shared address only touches documents sent on CapHive's platform account.
  def find_document(_connection_id, request_id)
    return if request_id.blank?

    doc = Document.find_by(provider_doc_id: request_id.to_s)
    doc if doc && ZohoSignAccount.for_document(doc).platform?
  end
end
