class DocusignEsignHelper
  include HTTParty
  include ApiCreator
  include DocusignEsignUtils

  debug_output $stdout if Rails.env.development?
  attr_accessor :debug

  BASE_URL = Rails.application.credentials[:DOCUSIGN_ACC_BASE_URI]
  DOCUSIGN_USER_ID = Rails.application.credentials[:DOCUSIGN_USER_ID]
  ACCOUNT_ID = Rails.application.credentials[:DOCUSIGN_API_ACC_ID]
  DOCUSIGN_RSA_PRIVATE_KEY = Rails.application.credentials[:DOCUSIGN_RSA_PRIVATE_KEY]
  DOCUSIGN_INTEGRATION_KEY = Rails.application.credentials[:DOCUSIGN_INTEGRATION_KEY]

  def args(entity_id)
    access_token = ::JwtAuth::JwtCreator.new.check_jwt_token(entity_id)
    {
      account_id: ACCOUNT_ID,
      base_path: BASE_URL,
      access_token:
    }
  end

  def send_document_for_esign(document)
    # if doc is not pdf then raise error
    raise "Only PDF files are supported for eSigning" unless document.file.mime_type.include?("pdf")

    # TODO: add support for docx files

    DocusignSigningViaEmailService.new(args(document.entity_id), document).worker
  end

  def update_document(response, document)
    response = ActiveSupport::HashWithIndifferentAccess.new(response)
    # Log the response from DocuSign API
    log_esign_response(document, response)

    if response[:envelope_id].present?
      document.update(sent_for_esign: true, sent_for_esign_date: Time.zone.now, provider_doc_id: response[:envelope_id], esign_status: "requested")
    else
      document.update(sent_for_esign: true, esign_status: "failed")

      document.e_signatures.each do |esign|
        esign.update(status: "failed")
      end
    end
  end

  def update_signature_progress(params)
    # we do not handle erronous webhook requests
    # they are logged and ignored
    if params["event"].blank?
      e = StandardError.new("eSign webhook not supported - \n #{params}")
      Rails.logger.error(e.message)
      ExceptionNotifier.notify_exception(e)
      return
    end
    doc = Document.find_by(provider_doc_id: params["data"]["envelopeId"])
    # a document may not be found if it has been deleted or been resent and now had a new envelope id
    if doc.blank?
      e = StandardError.new("Document not found for #{params}")
      Rails.logger.error(e.message)
      ExceptionNotifier.notify_exception(e)
      return
    end

    case params["event"]
    # envelope-voided is cancellation for docusign, triggered initially when a user cancels esigning
    when "envelope-voided"
      doc&.update(esign_status: "voided")
      doc.e_signatures.update_all(status: "voided")
      api_updates = params.dup
      api_updates['data']['envelopeSummary'] = params.dig('data', 'envelopeSummary')&.except('envelopeDocuments')
      # rubocop:enable Rails/SkipsModelValidations
      log_webhook_data(doc, api_updates)
    # envelope-completed is the final status for docusign, triggered when all signers have signed
    when "envelope-completed"
      signature_completed(doc)
      api_updates = params.dup
      api_updates['data']['envelopeSummary'] = params.dig('data', 'envelopeSummary')&.except('envelopeDocuments')
      log_webhook_data(doc, api_updates)
    # recipient-completed is triggered when a signer has signed
    when "recipient-completed"
      api_updates = params.dup
      api_updates['data']['envelopeSummary'] = params.dig('data', 'envelopeSummary')&.except('envelopeDocuments')
      esign = doc.e_signatures.order(:position)[(params["data"]["recipientId"].to_i - 1)]
      esign.update(status: "signed", api_updates: api_updates.to_s)
      log_webhook_data(doc, api_updates)
    # recipient-sent is triggered when a signer has been sent the document
    when "recipient-sent"
      api_updates = params.dup
      api_updates['data']['envelopeSummary'] = params.dig('data', 'envelopeSummary')&.except('envelopeDocuments')
      esign = doc.e_signatures.order(:position)[(params["data"]["recipientId"].to_i - 1)]
      esign.update(status: "sent", api_updates: api_updates.to_s)
      log_webhook_data(doc, api_updates)
    end
  end

  # fetch manual updates from docusign
  def update_esign_status(doc)
    if doc.esign_completed?
      # document already completed
      Rails.logger.debug { "Document #{doc.name} #{doc.id} already completed" }
    else
      envelope_api = create_envelope_api(args(doc.entity_id))
      envelope = get_envelope(envelope_api, doc)
      overall_status = envelope.status
      doc.assign_attributes(last_status_updated_at: Time.zone.now)
      if envelope && overall_status.present?
        doc.assign_attributes(esign_status: overall_status) unless overall_status.casecmp?("completed")
        recipients = get_recipients(envelope_api, doc)
        recipients.signers.each do |signer|
          esign = doc.e_signatures.find_by(email: signer.email)
          esign_status = if signer.status == "completed"
                           "signed"
                         else
                           "requested"
                         end
          esign.update(status: esign_status)
        end
        doc.save
        # Log manual status update
        log_manual_update_data(doc, { envelope_status: overall_status, recipients: recipients.signers.map { |s| { email: s.email, status: s.status } } })
      else
        signatures_failed(doc, envelope)
      end
    end
  end

  def signatures_failed(doc, envelope)
    e = StandardError.new("Error getting status for #{doc.name} - #{envelope}")
    ExceptionNotifier.notify_exception(e)
    doc.update(esign_status: "failed")
    Rails.logger.error e.message
  end

  def download(doc)
    envelope_api = create_envelope_api(args(doc.entity_id))
    envelope_api.get_document(ACCOUNT_ID, doc.id, doc.provider_doc_id)
  end

  def cancel_esign(doc)
    # error is handled in docusign_esigning.rb
    result, msg = cancel_docusign_api(doc)
    if result
      doc.e_signatures.each do |esign|
        esign.update(status: "cancelled")
      end
      doc.update(esign_status: "cancelled")
      # Log cancellation
      log_manual_update_data(doc, { action: "cancelled", reason: "Cancelled by Administrator" })
    else
      log_manual_update_data(doc, { action: "cancellation request", error: msg })
    end
    result
  end

  def cancel_docusign_api(doc)
    envelope_api = create_envelope_api(args(doc.entity_id))
    env = DocuSign_eSign::Envelope.new
    env.status = 'voided'
    env.voided_reason = 'Cancelled by Administrator'
    envelope_api.update(args(doc.entity_id)[:account_id], doc.provider_doc_id, env)
    [true, nil]
  rescue DocuSign_eSign::ApiError => e
    msg = handle_error(e)
    [false, msg]
  end

  def signature_completed(doc)
    file = download(doc)
    doc.signature_completed(file.path)
  end

  private

  # Log initial response when document is sent for eSigning
  def log_esign_response(document, response)
    request_data = {
      action: "send_for_esigning",
      document_name: document.name,
      document_id: document.id,
      timestamp: Time.zone.now
    }

    if document.esign_log.present?
      document.esign_log.update(request_data:, response_data: response)
      document.esign_log.save
    else
      EsignLog.create(entity_id: document.entity_id, document:, request_data:, response_data: response)
    end
  end

  # Log webhook data from DocuSign
  def log_webhook_data(doc, params)
    if doc.esign_log.present?
      doc.esign_log.webhook_data.present? ? doc.esign_log.webhook_data[Time.zone.now.to_s] = params : doc.esign_log.webhook_data = { "#{Time.zone.now}": params }
      doc.esign_log.save
    else
      EsignLog.create(entity_id: doc.entity_id, document: doc, webhook_data: { "#{Time.zone.now}": params })
    end
  end

  # Log manual status updates fetched from DocuSign
  def log_manual_update_data(doc, update_data)
    if doc.esign_log.present?
      doc.esign_log.manual_update_data.present? ? doc.esign_log.manual_update_data[Time.zone.now.to_s] = update_data : doc.esign_log.manual_update_data = { "#{Time.zone.now}": update_data }
      doc.esign_log.save
    else
      EsignLog.create(entity_id: doc.entity_id, document: doc, manual_update_data: { "#{Time.zone.now}": update_data })
    end
  end
end
