require 'base64'

class EsignHelper
  attr_accessor :provider, :helper, :doc, :user_id # Rails.env.development?

  def initialize(doc, provider: doc.entity.entity_setting.esign_provider, user_id: nil)
    @doc = doc
    @provider = provider
    @helper ||= "#{@provider.strip.capitalize}EsignHelper".constantize.new
    @user_id = user_id
  end

  def sign
    "#{@provider.strip.capitalize}Esigning".constantize.call(helper: @helper, doc: @doc, user_id: @user_id)
  end

  def retrieve_status
    helper.retrieve_status(doc)
  end

  def cancel_esign
    helper.cancel_esign(doc)
  end

  def extend_expiry(expire_by)
    helper.extend_expiry(doc, expire_by)
  end

  def send_reminder
    helper.send_reminder(doc)
  end

  # fetch manual updates from the provider. Returns whether anything actually changed (document
  # status or any signer's status), so callers can tell "we checked, nothing changed" apart from
  # "we checked, something changed" instead of always claiming an update happened.
  def update_esign_status
    status_before = doc.reload.esign_status
    signature_statuses_before = doc.e_signatures.reload.pluck(:id, :status).sort

    helper.update_esign_status(doc)
    check_and_update_document_status(doc)

    doc.reload
    signature_statuses_after = doc.e_signatures.reload.pluck(:id, :status).sort
    doc.esign_status != status_before || signature_statuses_after != signature_statuses_before
  end

  def check_and_update_document_status(document)
    unsigned_esigns = document.e_signatures.reload.where.not(status: "signed")
    # Some providers' own #update_esign_status already calls their check_and_update_document_status
    # internally (e.g. ZohoEsignHelper), which can mark the document completed via an atomic
    # update_all that doesn't refresh this in-memory `document` - reload so esign_completed? here
    # reflects that, instead of re-running signature_completed a second time for the same completion.
    document.reload
    helper.signature_completed(document) if unsigned_esigns.none? && !document.esign_completed?
  end

  # handles automatic callbacks
  def self.update_signature_progress(params)
    # identify which helper to use
    helper = nil
    if params.dig('data', 'envelopeId').present? && params.dig('data', 'accountId').present?
      helper = DocusignEsignHelper.new
    elsif params.dig('payload', 'document', 'id').present?
      helper = DigioEsignHelper.new
    else
      # Zoho webhooks never reach here: DocumentsController#signature_progress queues ZohoWebhookJob
      e = StandardError.new("eSign webhook not supported - \n #{params}")
      Rails.logger.error(e.message)
      ErrorReport.notify(e, source: "EsignHelper webhook")
      return
    end
    helper.update_signature_progress(params)
  end
end
