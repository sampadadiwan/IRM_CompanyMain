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

  # fetch manual updates
  def update_esign_status
    helper.update_esign_status(doc)
    check_and_update_document_status(doc)
  end

  def check_and_update_document_status(document)
    unsigned_esigns = document.e_signatures.reload.where.not(status: "signed")
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
      e = StandardError.new("eSign webhook not supported - \n #{params}")
      Rails.logger.error(e.message)
      ExceptionNotifier.notify_exception(e)
    end
    helper.update_signature_progress(params)
  end
end
