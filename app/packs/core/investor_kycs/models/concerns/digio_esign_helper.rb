require 'base64'

class DigioEsignHelper
  # Fixed-shape result returned by sign/validate_doc_size/update_document.
  # Callers access .success?, [:errors], and [:message] — Struct covers all three:
  # method access (.success, .errors, .message), predicate via the explicit success?
  # method, and symbol bracket access (Struct#[] already supports this).
  DigioResult = Struct.new(:success, :errors, :message) do
    def success? = success
  end
  include HTTParty

  MAX_SIZE_MB = 25
  MAX_SIZE_BYTES = MAX_SIZE_MB * 1024 * 1024
  AUDIT_TRAIL_TAG = "Audit Trail".freeze
  debug_output $stdout
  attr_accessor :debug # Rails.env.development?

  BASE_URL = ENV.fetch("DIGIO_BASE_URL", nil)
  AUTH_TOKEN = Base64.strict_encode64("#{Rails.application.credentials[:DIGIO_CLIENT_ID]}:#{Rails.application.credentials[:DIGIO_SECRET]}")

  def initialize
    super
    @debug = Rails.env.development?
  end

  def sign(document, user_id)
    response = send_document_for_esign(document)
    update_document(response, document, user_id)
  end

  def validate_doc_size(document, user_id = nil)
    # Document size should be less than 25MB
    tmpfile = document.file.download
    # Determine the size of the file
    file_size = File.size(tmpfile.path)
    tmpfile.close
    # unlink deletes the tempfile
    tmpfile.unlink

    # Calculate the decoded (original) size in bytes
    if file_size > MAX_SIZE_BYTES
      msg = "❌ Document size #{(file_size / 1024.0 / 1024.0).round(2)} MB exceeds size limit of #{MAX_SIZE_MB} MB."
      Rails.logger.error msg
      UserAlert.new(message: msg, user_id: user_id, level: :danger).broadcast if user_id.present?
      DigioResult.new(false, msg, nil)
    else
      DigioResult.new(true, nil, "Document size is within the limit.")
    end
  end

  def send_document_for_esign(document)
    # Open the file you wish to encode
    tmpfile = document.file.download
    data = File.read(tmpfile.path)
    # Encode the puppy
    encoded_file = Base64.strict_encode64(data)
    tmpfile.close
    # unlink deletes the tempfile
    tmpfile.unlink
    # fetch from esign
    display_on_page = document.display_on_page&.downcase || "last"
    body = prepare_data(document, document.name, encoded_file, display_on_page)

    auth_token = if document.entity.entity_setting.digio_cutover_date.present? && document.entity.entity_setting.digio_cutover_date < Time.zone.now
                   document.entity.entity_setting.digio_auth_token
                 else
                   AUTH_TOKEN
                 end

    response = hit_digio_esign_api(body, auth_token)
    if document.esign_log.present?
      document.esign_log.update(request_data: body.except(:file_data), response_data: response)
      document.esign_log.save
    else
      EsignLog.create(entity_id: document.entity_id, document:, request_data: body.except(:file_data), response_data: response)
    end

    response
  end

  # called after document is sent for esign to check response and update the document accordingly
  # if success then update the document with provider_doc_id and esign_status as requested
  # if failure then update the document with esign_status as failed
  def update_document(response, doc, user_id)
    json_res = JSON.parse(response.body)
    if response.success?
      doc.update(sent_for_esign: true, sent_for_esign_date: Time.zone.now, provider_doc_id: json_res["id"], esign_status: "requested")
      notify_ready_signers(doc)
      EsignUpdateJob.perform_later(doc.id, user_id) if doc.eligible_for_esign_update?
      DigioResult.new(true, nil, "Document - #{doc.name} sent for eSigning")
    else
      doc.update(sent_for_esign: true, esign_status: "failed", provider_doc_id: json_res["id"])

      doc.e_signatures.includes(:entity).find_each { |esign| esign.update(status: "failed") }
      msg = "Error sending #{doc.name} for eSigning - #{json_res['message']}"
      ErrorReport.notify(StandardError.new(msg), source: "DigioEsignHelper send", **ErrorReport.document_context(doc))
      Rails.logger.error msg
      DigioResult.new(false, msg, nil)
    end
  rescue JSON::ParserError => e
    # 502 bad gateway response cannot be parsed
    msg = "Error sending #{doc.name} for eSigning - #{e.message}"
    ErrorReport.notify(StandardError.new(msg), source: "DigioEsignHelper send", **ErrorReport.document_context(doc))
    Rails.logger.error msg
    DigioResult.new(false, msg, nil)
  end

  def retrieve_signed(esign_doc_id, auth_token)
    HTTParty.get(
      "#{BASE_URL}/v2/client/document/#{esign_doc_id}",
      headers: {
        "authorization" => "Basic #{auth_token}",
        'Content-Type' => 'application/json'
      },
      debug_output: @debug ? $stdout : nil
    )
  end

  def download(esign_doc_id, auth_token)
    HTTParty.get(
      "#{BASE_URL}/v2/client/document/download?document_id=#{esign_doc_id}",
      headers: {
        "authorization" => "Basic #{auth_token}",
        'Content-Type' => 'application/json'
      },
      debug_output: @debug ? $stdout : nil
    )
  end

  def download_audit_trail(esign_doc_id, auth_token)
    HTTParty.get(
      "#{BASE_URL}/v2/client/document/#{esign_doc_id}/v2/audit_log",
      headers: {
        "authorization" => "Basic #{auth_token}"
      },
      debug_output: @debug ? $stdout : nil
    )
  end

  #   private

  def prepare_data(doc, file_name, encoded_file, display_on_page = "last")
    # if file name bigger than 100 chars then truncate and add ... till 100 chars
    file_name = "#{file_name[0..96]}..." if file_name.length > 100
    sequential = doc.force_esign_order.nil? ? false : doc.force_esign_order
    data = {
      signers: prep_user_data(doc.e_signatures),
      expire_in_days: 90,
      notify_signers: true,
      send_sign_link: true,
      # true only needed for widget
      generate_access_token: false,
      display_on_page:,
      file_name:,
      file_data: encoded_file
    }
    data[:sequential] = sequential if sequential
    if doc.stamp_papers.present?
      tags = {}
      doc.stamp_papers.each do |stamp_paper|
        stamp_paper.tags.split(",").each do |tag|
          tags[tag.split(":").first.strip] = tag.split(":").last.strip.to_i
        end
      end
      stamp_paper = doc.stamp_papers.first
      data[:estamp_request] = {
        tags:,
        sign_on_page: stamp_paper.sign_on_page.upcase,
        note_content: stamp_paper.notes,
        note_on_page: stamp_paper.note_on_page.upcase
      }
    end
    data
  end

  def prep_user_data(esigns)
    ret = []
    esigns.order(:position).each do |esign|
      email = esign.email
      sign_type = esign.signature_type&.downcase || "aadhaar"
      reason = nil # fetch from esign or doc
      hash = {
        identifier: email,
        # name: u.full_name, #not mandatory
        sign_type:
      }
      hash[:reason] = reason if reason.present?
      ret << hash
    end
    ret
  end

  def hit_cancel_esign_api(provider_doc_id, auth_token)
    HTTParty.post(
      "#{BASE_URL}/v2/client/document/#{provider_doc_id}/cancel",
      headers: {
        "authorization" => "Basic #{auth_token}",
        'Content-Type' => 'application/json'
      }
    )
  end

  def cancel_esign(doc)
    response = hit_cancel_esign_api(doc.provider_doc_id, auth_token_for(doc))
    if response.success?
      # added transaction to avoid partial updates
      ActiveRecord::Base.transaction do
        doc.e_signatures.includes(:entity).find_each { |esign| esign.update(status: "cancelled") }
        doc.update(esign_status: "cancelled")
      end
    else
      e = StandardError.new("Error cancelling #{doc.name}")
      Rails.logger.error e.message
    end
    if doc.esign_log.present?
      doc.esign_log.manual_update_data.present? ? doc.esign_log.manual_update_data[Time.zone.now.to_s] = response.body : doc.esign_log.manual_update_data = { "#{Time.zone.now}": response.body }
      doc.esign_log.save
    else
      EsignLog.create(entity_id: doc.entity_id, document: doc, manual_update_data: { "#{Time.zone.now}": response.body })
    end
  end

  # fetch manual updates from digio
  def update_esign_status(doc)
    if doc.esign_completed?
      # document already completed
      Rails.logger.debug { "Document #{doc.name} #{doc.id} already completed" }
    else
      # Get api response

      response = retrieve_signed(doc.provider_doc_id, auth_token_for(doc))
      overall_status = JSON.parse(response.body)["status"].presence || JSON.parse(response.body)["agreement_status"] # can be "completed" or "requested"
      if response.success? && overall_status.present?
        # not updating to completed as check_and_update_document_status does it
        # if done here it wont download the signed document
        doc.update(esign_status: overall_status) unless overall_status.casecmp?("completed")
        # Update each esignature's status
        esigns_by_email = doc.e_signatures.includes(:entity).index_by { |e| e.email.downcase }
        response['signing_parties'].each do |signer|
          esign = esigns_by_email[signer['identifier']&.downcase]
          esign&.update_esign_response(signer['status'])
        end
        notify_ready_signers(doc)
      else
        signatures_failed(doc)
      end
      if doc.esign_log.present?
        doc.esign_log.manual_update_data.present? ? doc.esign_log.manual_update_data[Time.zone.now.to_s] = response.body : doc.esign_log.manual_update_data = { "#{Time.zone.now}": response.body }
        doc.esign_log.save
      else
        EsignLog.create(entity_id: doc.entity_id, document: doc, manual_update_data: { "#{Time.zone.now}": response.body })
      end
    end
  end

  # handles Digio automatic callbacks
  # Routed on the notification's event type (doc.signed, doc.sign.failed, doc.sign.rejected). A blank or
  # unknown event is decided by its content, exactly as before events were read, so older payloads and
  # events we do not know never change behaviour.
  # Worked examples H6-H8, E21-E28 — openspec/changes/embedded-esign-digio/design.md#worked-examples
  def update_signature_progress(params)
    if params.dig('payload', 'document', 'id').present?
      case params['event'].to_s.downcase
      when 'doc.signed'
        process_esign_success(params)
      when 'doc.sign.failed'
        process_esign_failure(params)
      when 'doc.sign.rejected'
        process_esign_rejected(params)
      else
        process_esign_by_content(params)
      end
    else
      e = StandardError.new("Document not found for #{params}")
      ErrorReport.notify(e, source: "DigioEsignHelper webhook")
      Rails.logger.error e.message
    end
  end

  def check_and_update_document_status(document)
    unsigned_esigns = document.e_signatures.reload.where.not(status: "signed")
    signature_completed(document) if unsigned_esigns.none? && !document.esign_completed?
  end

  # X14: without the signed copy the document is not completed, so the next notification or status check tries again.
  def signature_completed(doc)
    response = DigioEsignHelper.new.download(doc.provider_doc_id, auth_token_for(doc))
    unless response.success?
      e = StandardError.new("Could not download the signed copy of #{doc.name} - #{response.code}")
      ErrorReport.notify(e, source: "DigioEsignHelper#signature_completed", **ErrorReport.document_context(doc))
      Rails.logger.error e.message
      return
    end

    tmpfile = Tempfile.new([doc.name.to_s, ".pdf"], encoding: 'ascii-8bit')
    tmpfile.write(response.body)
    tmpfile.flush
    # Only on the call that completed the document: this runs once per notification and status check
    DigioAuditTrailJob.perform_later(doc.id) if doc.signature_completed(tmpfile.path)
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  # Files Digio's audit trail beside the signed copy, once. Raises when Digio does not hand it over (it answers 403
  # until the signing flow is complete) so DigioAuditTrailJob retries. Worked examples H11, E36-E37, X13 —
  # openspec/changes/embedded-esign-digio/design.md#worked-examples
  def attach_audit_trail(doc)
    return if Document.exists?(from_template_id: doc.id, owner_tag: AUDIT_TRAIL_TAG)

    response = download_audit_trail(doc.provider_doc_id, auth_token_for(doc))
    raise StandardError, "Could not download the audit trail of #{doc.name} - #{response.code}" unless response.success?

    tmpfile = Tempfile.new([doc.name.to_s, "_audit_trail.pdf"], encoding: 'ascii-8bit')
    tmpfile.write(response.body)
    tmpfile.flush
    attached = doc.attach_esign_supplementary_document(tmpfile.path, name_suffix: AUDIT_TRAIL_TAG, owner_tag: AUDIT_TRAIL_TAG)
    raise StandardError, "Could not save the audit trail of #{doc.name}" unless attached
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  private

  # A document sent before the entity's cutover stays with the account that sent it
  def auth_token_for(doc)
    if doc.entity.entity_setting.digio_cutover_date.present? && doc.entity.entity_setting.digio_cutover_date < doc.sent_for_esign_date
      doc.entity.entity_setting.digio_auth_token
    else
      AUTH_TOKEN
    end
  end

  def hit_digio_esign_api(body, auth_token)
    HTTParty.post(
      "#{BASE_URL}/v2/client/document/uploadpdf",
      headers: {
        "authorization" => "Basic #{auth_token}",
        'Content-Type' => 'application/json'
      },
      body: body.to_json,
      debug_output: @debug ? $stdout : nil
    )
  end

  # A notification without a recognised event: an error code means failure, otherwise it lists signers
  def process_esign_by_content(params)
    if params.dig('payload', 'document', 'error_code').blank?
      process_esign_success(params)
    else
      process_esign_failure(params)
    end
  end

  # used in digio callbacks
  def process_esign_success(params)
    provider_doc_id = params.dig('payload', 'document', 'id')
    doc = Document.find_by(provider_doc_id:)
    if doc.present?
      signing_parties = params.dig('payload', 'document', 'signing_parties')
      if signing_parties.blank?
        # e.g. a rejection-shaped payload: there is nothing to update, but someone should know
        ErrorReport.notify(StandardError.new("eSign notification for #{doc.name} lists no signing_parties - #{params}"),
                           source: "DigioEsignHelper webhook", **ErrorReport.document_context(doc))
        return
      end

      # update contains the statuses of all signing parties
      signing_parties.each do |signer|
        esign = doc.e_signatures.find_by(email: signer['identifier']&.downcase)
        esign&.update_esign_response(signer['status'])
      end
      notify_ready_signers(doc)
      if doc.esign_log.present?
        doc.esign_log.webhook_data.present? ? doc.esign_log.webhook_data[Time.zone.now.to_s] = params : doc.esign_log.webhook_data = { "#{Time.zone.now}": params }
        doc.esign_log.save
      else
        EsignLog.create(entity_id: doc.entity_id, document: doc, webhook_data: { "#{Time.zone.now}": params })
      end
      check_and_update_document_status(doc)
    else
      report_unmatched_document(params)
    end
  end

  # used in digio callbacks
  def process_esign_failure(params)
    doc = Document.find_by(provider_doc_id: params.dig('payload', 'document', 'id'))
    email = params.dig('payload', 'document', 'signer_identifier')&.downcase
    if doc.present?
      esign = doc.e_signatures.find_by(email:)
      esign&.update_esign_response("failed")
      ErrorReport.notify(StandardError.new("eSign not found for #{doc&.name} and email #{email} - #{params}"), source: "DigioEsignHelper webhook", signer_email: email, **ErrorReport.document_context(doc)) if esign.blank?
      if doc.esign_log.present?
        doc.esign_log.webhook_data.present? ? doc.esign_log.webhook_data[Time.zone.now.to_s] = params : doc.esign_log.webhook_data = { "#{Time.zone.now}": params }
        doc.esign_log.save
      else
        EsignLog.create(entity_id: doc.entity_id, document: doc, webhook_data: { "#{Time.zone.now}": params })
      end
    else
      report_unmatched_document(params)
    end
  end

  # A signer rejected the document at Digio (doc.sign.rejected). The payload has the signer's identifier but
  # no signing_parties, so it must not go through the success path. Support is always told: a rejection
  # leaves the document stuck until the GP acts. The document itself is left as it is.
  def process_esign_rejected(params)
    doc = Document.find_by(provider_doc_id: params.dig('payload', 'document', 'id'))
    return report_unmatched_document(params) if doc.blank?

    email = params.dig('payload', 'document', 'signer_identifier')&.strip&.downcase
    esign = doc.e_signatures.find_by("LOWER(e_signatures.email) = ?", email) if email.present?
    esign&.update_esign_response("rejected")
    if doc.esign_log.present?
      doc.esign_log.webhook_data.present? ? doc.esign_log.webhook_data[Time.zone.now.to_s] = params : doc.esign_log.webhook_data = { "#{Time.zone.now}": params }
      doc.esign_log.save
    else
      EsignLog.create(entity_id: doc.entity_id, document: doc, webhook_data: { "#{Time.zone.now}": params })
    end
    ErrorReport.notify(StandardError.new("eSign rejected for #{doc.name} by #{email.presence || 'unknown signer'}#{' (signer not found)' if esign.blank?}"),
                       source: "DigioEsignHelper webhook", signer_email: email, **ErrorReport.document_context(doc))
  end

  # Tells the signers whose turn it is (embedded eSigning). Never lets a notification problem fail a send, a status
  # update or a webhook acknowledgement: it is reported and the caller carries on.
  def notify_ready_signers(doc)
    doc.notify_ready_signers
  rescue StandardError => e
    ErrorReport.notify(e, source: "Document notify_ready_signers", **ErrorReport.document_context(doc))
  end

  # The notification names a document we do not have: acknowledge it (the caller always answers success), tell support
  def report_unmatched_document(params)
    provider_doc_id = params.dig('payload', 'document', 'id')
    Rails.logger.error "Document not found for digio provider_doc_id #{provider_doc_id}"
    ErrorReport.notify(StandardError.new("eSign notification for unknown digio document #{provider_doc_id}"),
                       source: "DigioEsignHelper webhook")
  end

  def signatures_failed(doc)
    e = StandardError.new("Error getting status for #{doc.name}")
    ErrorReport.notify(e, source: "DigioEsignHelper#signatures_failed", **ErrorReport.document_context(doc))
    doc.update(esign_status: "failed")
    Rails.logger.error e.message
  end
end
# rubocop:enable Metrics/ClassLength
