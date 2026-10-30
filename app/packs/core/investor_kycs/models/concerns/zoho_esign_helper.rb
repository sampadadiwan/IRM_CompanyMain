require 'base64'
require 'openssl'

class ZohoEsignHelper
  # Fixed-shape result returned by send_document_for_esign/update_document.
  # Mirrors DigioEsignHelper::DigioResult - callers access .success?, [:errors], [:message].
  ZohoResult = Struct.new(:success, :errors, :message) do
    def success? = success
  end

  MAX_SIZE_MB = 25
  MAX_SIZE_BYTES = MAX_SIZE_MB * 1024 * 1024
  MAX_SIGNERS = 25

  DEFAULT_EXPIRATION_DAYS = 90
  MAX_EXPIRATION_DAYS = 99

  DEFAULT_REMINDER_PERIOD_DAYS = 4
  MAX_REMINDER_PERIOD_DAYS = 30

  # Zoho's field x_coord/y_coord/abs_width/abs_height are absolute PDF points, which Zoho
  # converts internally against the document's actual page size - confirmed by comparing
  # submitted values against the x_value/y_value/width/height percentages Zoho returned for
  # an A4 (595x842pt) document. y increases downward from the top of the page.
  PAGE_WIDTH_PT = 595
  PAGE_HEIGHT_PT = 842
  # 3x the original 20x5 - that was barely visible (~3% x 0.6% of an A4 page).
  SIGNATURE_FIELD_WIDTH = 60
  SIGNATURE_FIELD_HEIGHT = 15
  SIGNATURE_FIELD_MARGIN = 15
  SIGNATURE_FIELD_GAP = 12

  # Zoho request_status -> documents.esign_status. "completed" is deliberately absent: a document
  # only completes through the completion rule, which also downloads the signed copy and
  # certificate. Anything not listed changes nothing and stays in the eSign log (H9, E30, X23).
  REQUEST_STATUSES = {
    "inprogress" => "inprogress",
    "expired" => "expired",
    "recalled" => "cancelled",
    "declined" => "failed"
  }.freeze

  # Zoho action_status -> e_signatures.status; unknown values change nothing (X23).
  ACTION_STATUSES = {
    "SIGNED" => "signed", "COMPLETED" => "signed", "APPROVED" => "signed",
    "DECLINED" => "failed",
    "VIEWED" => "requested", "UNOPENED" => "requested", "NOACTION" => "requested", "WAITING_FOR_MY_TURN" => "requested",
    "WAITING_FOR_OTHERS" => "requested", "YET_TO_SIGN" => "requested", "FORWARDED" => "requested"
  }.freeze

  def sign(document, user_id)
    response = send_document_for_esign(document)
    update_document(response, document, user_id)
  end

  def validate_doc_size(document, user_id = nil)
    tmpfile = document.file.download
    file_size = File.size(tmpfile.path)
    tmpfile.close
    tmpfile.unlink

    if file_size > MAX_SIZE_BYTES
      msg = "❌ Document size #{(file_size / 1024.0 / 1024.0).round(2)} MB exceeds size limit of #{MAX_SIZE_MB} MB."
      Rails.logger.error msg
      UserAlert.new(message: msg, user_id: user_id, level: :danger).broadcast if user_id.present?
      ZohoResult.new(false, msg, nil)
    else
      ZohoResult.new(true, nil, "Document size is within the limit.")
    end
  end

  # Creates the signature request, then submits it with a default signature field placed for each
  # recipient (on the first, last or every page, per document.display_on_page). Raises
  # ZohoSignClient::Error or PDF::Reader::MalformedPDFError; ZohoEsigning turns those into a
  # Failed document.
  def send_document_for_esign(document)
    # A send (or resend) always goes on the account the company uses now, whatever an earlier send used
    client = client_for(document, ZohoSignAccount.for_entity(document.entity))
    tmpfile = document.file.download
    page_count = PDF::Reader.new(tmpfile.path).page_count
    created = File.open(tmpfile.path) { |file| client.create_request(data: request_data(document), file:) }
    request_id = created["request_id"]

    begin
      submitted = client.submit_request(request_id, submit_actions(created, page_count, document))
    rescue ZohoSignClient::Error
      delete_draft(client, document, request_id)
      raise
    end

    log_esign_response(document, { create: created, submit: submitted })
    { request_id:, actions: created["actions"] }
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  # Called once the request is created and submitted in Zoho.
  def update_document(response, doc, user_id)
    # Approximate until the next status fetch reconciles it against Zoho's own expire_by
    # (see #apply_request_details) - Zoho's exact timestamp can differ slightly (time-of-day,
    # rounding), but this gives the UI something to show immediately instead of nothing.
    doc.update(sent_for_esign: true, sent_for_esign_date: Time.zone.now, provider_doc_id: response[:request_id], esign_status: "requested",
               esign_expires_at: expiration_days_for(doc).days.from_now)
    store_signer_ids(doc, response[:actions])
    EsignUpdateJob.perform_later(doc.id, user_id) if doc.eligible_for_esign_update?
    ZohoResult.new(true, nil, "Document - #{doc.name} sent for eSigning")
  end

  # X13, X14, X15: the document is Failed (and therefore resendable), the sender gets the reason.
  def send_failed(doc, error)
    msg = "Error sending #{doc.name} for eSigning - #{error.message}"
    doc.update(sent_for_esign: true, esign_status: "failed")
    doc.e_signatures.includes(:entity).find_each do |esign|
      esign.add_api_update(msg)
      esign.update(status: "failed", api_updates: esign.api_updates)
    end
    log_esign_response(doc, { error: msg })
    ErrorReport.notify(error, source: "ZohoEsignHelper send", **ErrorReport.document_context(doc))
    Rails.logger.error msg
    ZohoResult.new(false, msg, nil)
  end

  # X25: a refused or failed recall leaves everything as it was.
  def cancel_esign(doc)
    response = client_for(doc).recall(doc.provider_doc_id)
    ActiveRecord::Base.transaction do
      doc.e_signatures.includes(:entity).find_each do |esign|
        esign.add_api_update(response)
        esign.update(status: "cancelled", api_updates: esign.api_updates)
      end
      doc.update(esign_status: "cancelled")
    end
    log_manual_update_data(doc, response)
    true
  rescue ZohoSignClient::Error => e
    log_failed_action(doc, "cancel", e)
    false
  end

  # E21-E24, X16: any real date from tomorrow on - no upper limit and never shortened; anything else
  # is refused before Zoho is called. X17: Zoho's own refusal leaves the expiry unchanged.
  def extend_expiry(doc, expire_by)
    date = parse_extension_date(expire_by)
    return ZohoResult.new(false, "Choose a date from #{I18n.l(Date.tomorrow)} onward.", nil) if date.nil? || date < Date.tomorrow

    response = client_for(doc).extend(doc.provider_doc_id, date)
    doc.update(esign_expires_at: date.end_of_day)
    log_manual_update_data(doc, response)
    ZohoResult.new(true, nil, "Document's eSignature expiry was extended")
  rescue ZohoSignClient::Error => e
    log_failed_action(doc, "extend", e)
    ZohoResult.new(false, "Error extending eSignature expiry", nil)
  end

  # Sends an immediate reminder email to whichever recipient(s) still need to sign. Separate from
  # the automatic email_reminders/reminder_period set on create, which only controls Zoho's own
  # recurring reminder schedule. Never called from a retried job - each call emails the signers.
  def send_reminder(doc)
    response = client_for(doc).remind(doc.provider_doc_id)
    log_manual_update_data(doc, response)
    true
  rescue ZohoSignClient::Error => e
    log_failed_action(doc, "remind", e)
    false
  end

  # Pull: "Get eSignatures' updates" and the daily check. TransientError / RateLimited / AuthError
  # propagate so EsignUpdateJob can retry or discard them; the document is never Failed by them
  # (X9, X10). Only a Zoho refusal of the request itself fails the document.
  def update_esign_status(doc)
    if doc.esign_completed?
      Rails.logger.debug { "Document #{doc.name} #{doc.id} already completed" }
      return
    end

    json = client_for(doc).get_request(doc.provider_doc_id)
    apply_request_details(doc, json)
    log_manual_update_data(doc, json)
  rescue ZohoSignClient::RequestError => e
    signatures_failed(doc, e)
  end

  # Applies one verified Zoho webhook event to its document (ZohoWebhookJob found and scoped it).
  # Writes are absolute and completion is claimed once, so a replayed or out-of-order event is
  # harmless (E27, E28). Payload shape: zoho esign docs/webhooks-management.pdf
  def update_signature_progress(doc, payload)
    case payload.dig("notifications", "operation_type")
    when "RequestSubmitted"
      # H15: only signers Zoho hasn't reported on yet
      doc.e_signatures.where(status: [nil, ""]).update_all(status: "sent")
    when "RequestSigningSuccess"
      update_esign_for_recipient(doc, payload, "signed")
      check_and_update_document_status(doc)
    when "RequestRejected"
      # X24: Zoho ends the request on a decline; Failed makes the document resendable
      update_esign_for_recipient(doc, payload, "failed")
      doc.update(esign_status: "failed")
    when "RequestForwarded"
      # E29: the slot stays with the original signer; the forward is recorded on it
      esign = recipient_for(doc, payload)
      esign&.update(api_updates: esign.add_api_update(payload))
    when "RequestRecalled"
      doc.update(esign_status: "cancelled")
      doc.e_signatures.update_all(status: "cancelled")
    when "RequestExpired"
      # E31
      doc.update(esign_status: "expired")
      doc.e_signatures.update_all(status: "expired")
    when "RequestCompleted"
      # H10, E28
      check_and_update_document_status(doc)
    end
    # RequestViewed and anything else (E35) are only logged
    log_webhook_data(doc, payload)
  end

  def check_and_update_document_status(document)
    unsigned_esigns = document.e_signatures.reload.where.not(status: "signed")
    signature_completed(document) if unsigned_esigns.none? && !document.esign_completed?
  end

  def signature_completed(doc)
    tmpfile = Tempfile.new([doc.name.to_s, ".pdf"], encoding: 'ascii-8bit')
    tmpfile.write(client_for(doc).download_pdf(doc.provider_doc_id))
    tmpfile.flush
    newly_completed = doc.signature_completed(tmpfile.path)

    # Zoho's own #update_esign_status calls check_and_update_document_status internally, and
    # EsignHelper#update_esign_status calls it again straight after - so this can run twice for
    # the same completion. Only fetch/attach the certificate on the call that actually completed
    # the document (see Document#signature_completed), or it ends up attached twice.
    attach_completion_certificate(doc) if newly_completed
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  # Verifies the X-ZS-WEBHOOK-SIGNATURE header (HMAC-SHA256, base64) against the raw request
  # body, per zoho esign docs/securing-zoho-sign-webhooks-with-hmac-authentication.pdf.
  # X18, X19: a missing or wrong signature is refused. Without a secret, updates are only accepted
  # in development and test (E34); staging and production refuse them (X22).
  def self.verify_signature(raw_body, signature, secret)
    if secret.blank?
      Rails.logger.warn("Zoho Sign webhook accepted without a signature check - no webhook secret configured") if unsigned_webhooks_allowed?
      return unsigned_webhooks_allowed?
    end
    return false if signature.blank?

    expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, raw_body))
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end

  def self.unsigned_webhooks_allowed?
    Rails.env.local?
  end

  private

  # One client per document's account for the life of this helper (a job or a request).
  def client_for(doc, account = nil)
    @clients ||= {}
    @clients[doc.id] ||= ZohoSignClient.new(account || ZohoSignAccount.for_document(doc))
  end

  # E29: Zoho's action_id stays with the signer slot when a signer forwards the request, so it is
  # matched first; the email covers documents sent before action ids were stored.
  def signer_for(doc, action_id, email)
    signers = doc.e_signatures.to_a
    signers.find { |esign| action_id.present? && esign.provider_signer_id == action_id.to_s } ||
      signers.find { |esign| esign.email.to_s.casecmp?(email.to_s) }
  end

  # The action ids Zoho gave each signer when the request was created, matched by email (falling
  # back to the signer order the request was built in).
  def store_signer_ids(doc, actions)
    signers = doc.e_signatures.order(:position).to_a
    Array(actions).each_with_index do |action, idx|
      esign = signers.find { |s| s.email.to_s.casecmp?(action["recipient_email"].to_s) } || signers[idx]
      esign&.update_column(:provider_signer_id, action["action_id"].to_s)
    end
  end

  # The extend dialog posts yyyy-mm-dd; anything else (tampered or blank) is not a date.
  def parse_extension_date(value)
    value.is_a?(Date) ? value : Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  # X15: a draft Zoho created but never sent would otherwise pile up in the account. Best effort.
  def delete_draft(client, document, request_id)
    client.delete_request(request_id) if request_id.present?
  rescue ZohoSignClient::Error => e
    Rails.logger.warn("Zoho Sign draft #{request_id} for document #{document.id} not deleted - #{e.message}")
  end

  # Status, expiry and signers from Zoho's "get details" response.
  def apply_request_details(doc, json)
    request = json["requests"] || {}
    attrs = {}
    status = REQUEST_STATUSES[request["request_status"].to_s.downcase]
    attrs[:esign_status] = status if status
    # E25: Zoho's expire_by (epoch ms) is authoritative - it moves after an extension made anywhere.
    attrs[:esign_expires_at] = Time.zone.at(request["expire_by"].to_i / 1000) if request["expire_by"].present?
    doc.update(attrs) if attrs.any?
    log_unknown_status(doc, "request_status", request["request_status"]) if status.nil? && !request["request_status"].to_s.casecmp?("completed")

    (request["actions"] || []).each do |action|
      signer_status = ACTION_STATUSES[action["action_status"].to_s.upcase]
      next log_unknown_status(doc, "action_status", action["action_status"]) if signer_status.nil?

      signer_for(doc, action["action_id"], action["recipient_email"])&.update_esign_response(signer_status, json)
    end
    check_and_update_document_status(doc)
  end

  def log_unknown_status(doc, field, value)
    Rails.logger.warn("Zoho Sign #{field} #{value.inspect} not mapped - document #{doc.id} (#{doc.provider_doc_id}) unchanged")
  end

  def log_failed_action(doc, action, error)
    Rails.logger.warn("Zoho Sign #{action} failed for document #{doc.id} (#{doc.provider_doc_id}) - #{error.message}")
    log_manual_update_data(doc, { action:, error: error.message })
  end

  # X26: Zoho's signed PDF doesn't include the audit-trail certificate; it is fetched separately.
  # If it can't be, the document stays Completed with its signed copy and the failure is reported.
  def attach_completion_certificate(doc)
    content = client_for(doc).completion_certificate(doc.provider_doc_id)
    tmpfile = Tempfile.new([doc.name.to_s, "_certificate.pdf"], encoding: 'ascii-8bit')
    tmpfile.write(content)
    tmpfile.flush
    doc.attach_esign_supplementary_document(tmpfile.path, name_suffix: "Signature Certificate", owner_tag: "Signature Certificate")
  rescue ZohoSignClient::Error => e
    ErrorReport.notify(e, source: "ZohoEsignHelper completion certificate", **ErrorReport.document_context(doc))
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  # Shared by request_data (what we tell Zoho) and update_document (our own approximate
  # esign_expires_at, set immediately at send time).
  def expiration_days_for(document)
    (document.esign_expiration_days.presence || DEFAULT_EXPIRATION_DAYS).to_i.clamp(1, MAX_EXPIRATION_DAYS)
  end

  # "First" -> page 0; "All" -> every page; "Last", blank, or anything else -> the last page
  # (the historical default, kept for documents saved before this field existed).
  def signature_page_numbers(display_on_page, page_count)
    case display_on_page&.downcase
    when "first" then [0]
    when "all" then (0...page_count).to_a
    else [page_count - 1]
    end
  end

  # H7 (configured values), E13 (defaults 90 / 4), E20 (forced order -> sequential)
  def request_data(document)
    actions = document.e_signatures.order(:position).map.with_index do |esign, idx|
      {
        action_type: "SIGN",
        recipient_email: esign.email,
        recipient_name: esign.email,
        signing_order: document.force_esign_order ? idx : 0,
        verify_recipient: false,
        private_notes: "Please sign #{document.name}"
      }
    end

    {
      requests: {
        request_name: document.name.to_s[0, 100],
        actions:,
        expiration_days: expiration_days_for(document),
        is_sequential: document.force_esign_order || false,
        email_reminders: document.esign_email_reminders,
        reminder_period: (document.esign_reminder_period.presence || DEFAULT_REMINDER_PERIOD_DAYS).to_i.clamp(1, MAX_REMINDER_PERIOD_DAYS)
      }
    }
  end

  # E18, E19: one default signature field per recipient, on the page(s) per
  # document.display_on_page ("First"/"Last"/"All" - mirrors DigioEsignHelper#prepare_data).
  # Fields are anchored to the bottom-right corner and stacked upward per recipient so
  # multiple signers don't get overlapping boxes.
  def submit_actions(created, page_count, document)
    document_id = created.dig("document_ids", 0, "document_id")
    page_nos = signature_page_numbers(document.display_on_page, page_count)
    x_coord = PAGE_WIDTH_PT - SIGNATURE_FIELD_MARGIN - SIGNATURE_FIELD_WIDTH
    base_y_coord = PAGE_HEIGHT_PT - SIGNATURE_FIELD_MARGIN - SIGNATURE_FIELD_HEIGHT

    (created["actions"] || []).each_with_index.map do |action, idx|
      y_coord = base_y_coord - (idx * (SIGNATURE_FIELD_HEIGHT + SIGNATURE_FIELD_GAP))
      {
        action_id: action["action_id"],
        action_type: action["action_type"],
        verify_recipient: action["verify_recipient"],
        private_notes: action["private_notes"],
        signing_order: action["signing_order"],
        # field_name must be unique per field within the request - only matters when placing on
        # multiple pages ("All"), since a single first/last field keeps the plain "Signature" name.
        fields: page_nos.map do |page_no|
          {
            field_name: page_nos.size > 1 ? "Signature_#{page_no + 1}" : "Signature",
            field_type_name: "Signature",
            field_category: "image",
            field_label: "Signature",
            is_mandatory: true,
            page_no:,
            document_id:,
            action_id: action["action_id"],
            x_coord:,
            y_coord:,
            abs_width: SIGNATURE_FIELD_WIDTH,
            abs_height: SIGNATURE_FIELD_HEIGHT
          }
        end
      }
    end
  end

  def update_esign_for_recipient(doc, payload, status)
    esign = recipient_for(doc, payload)
    esign&.update_esign_response(status, payload)
  end

  def recipient_for(doc, payload)
    action_id = payload.dig("notifications", "action_id")
    email = payload.dig("notifications", "performed_by_email")
    esign = signer_for(doc, action_id, email)
    Rails.logger.warn("Zoho Sign webhook: no signer #{action_id} / #{email} on document #{doc.id}") if esign.nil?
    esign
  end

  # Only a Zoho refusal of the request (not a timeout, rate limit or credential problem) fails it.
  def signatures_failed(doc, error)
    doc.update(esign_status: "failed")
    doc.e_signatures.includes(:entity).find_each do |esign|
      esign.add_api_update(error.message)
      esign.save!
    end
    log_manual_update_data(doc, { error: error.message })
    ErrorReport.notify(error, source: "ZohoEsignHelper status", **ErrorReport.document_context(doc))
  end

  # Log initial response when document is sent for eSigning
  def log_esign_response(document, response)
    response = strip_image_strings(response)
    if document.esign_log.present?
      document.esign_log.update(request_data: { action: "send_for_esigning" }, response_data: response)
      document.esign_log.save
    else
      EsignLog.create(entity_id: document.entity_id, document:, request_data: { action: "send_for_esigning" }, response_data: response)
    end
  end

  # Zoho's document/page payloads embed a base64 "image_string" thumbnail per page - useless
  # for our logs and large enough to bloat the esign_log row, so strip it before persisting.
  def strip_image_strings(data)
    data = JSON.parse(data) if data.is_a?(String)
    case data
    when Hash
      data.each_with_object({}) { |(k, v), result| result[k] = strip_image_strings(v) unless k.to_s == "image_string" }
    when Array
      data.map { |v| strip_image_strings(v) }
    else
      data
    end
  rescue JSON::ParserError
    data
  end

  # Log webhook data from Zoho Sign
  def log_webhook_data(doc, params)
    if doc.esign_log.present?
      doc.esign_log.webhook_data.present? ? doc.esign_log.webhook_data[Time.zone.now.to_s] = params : doc.esign_log.webhook_data = { "#{Time.zone.now}": params }
      doc.esign_log.save
    else
      EsignLog.create(entity_id: doc.entity_id, document: doc, webhook_data: { "#{Time.zone.now}": params })
    end
  end

  # Log manual status updates fetched from Zoho Sign
  def log_manual_update_data(doc, update_data)
    update_data = strip_image_strings(update_data)
    if doc.esign_log.present?
      doc.esign_log.manual_update_data.present? ? doc.esign_log.manual_update_data[Time.zone.now.to_s] = update_data : doc.esign_log.manual_update_data = { "#{Time.zone.now}": update_data }
      doc.esign_log.save
    else
      EsignLog.create(entity_id: doc.entity_id, document: doc, manual_update_data: { "#{Time.zone.now}": update_data })
    end
  end
end
