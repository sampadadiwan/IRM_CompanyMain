require 'base64'

class DigioEsignHelper
  include HTTParty
  debug_output $stdout
  attr_accessor :debug # Rails.env.development?

  BASE_URL = ENV.fetch("DIGIO_BASE_URL", nil)
  AUTH_TOKEN = Base64.strict_encode64("#{Rails.application.credentials[:DIGIO_CLIENT_ID]}:#{Rails.application.credentials[:DIGIO_SECRET]}")

  def initialize
    super
    @debug = Rails.env.development?
  end

  def sign(document)
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

    response = HTTParty.post(
      "#{BASE_URL}/v2/client/document/uploadpdf",
      headers: {
        "authorization" => "Basic #{auth_token}",
        'Content-Type' => 'application/json'
      },
      body: body.to_json,
      debug_output: @debug ? $stdout : nil
    )

    Rails.logger.debug response
    response
  end

  def retrieve_signed(esign_doc_id, auth_token)
    response = HTTParty.get(
      "#{BASE_URL}/v2/client/document/#{esign_doc_id}",
      headers: {
        "authorization" => "Basic #{auth_token}",
        'Content-Type' => 'application/json'
      },
      debug_output: @debug ? $stdout : nil
    )

    Rails.logger.debug response

    response
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

  #   private

  def prepare_data(doc, file_name, encoded_file, display_on_page = "last")
    # if file name bigger than 100 chars then truncate and add ... till 100 chars
    file_name = "#{file_name[0..96]}..." if file_name.length > 100
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
      sign_type = esign.signature_type.downcase || "aadhaar"
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
    response = HTTParty.post(
      "#{BASE_URL}/v2/client/document/#{provider_doc_id}/cancel",
      headers: {
        "authorization" => "Basic #{auth_token}",
        'Content-Type' => 'application/json'
      }
    )

    Rails.logger.debug response
    response
  end

  def cancel_esign(doc)
    auth_token = if doc.entity.entity_setting.digio_cutover_date.present? && doc.entity.entity_setting.digio_cutover_date < doc.sent_for_esign_date
                   doc.entity.entity_setting.digio_auth_token
                 else
                   AUTH_TOKEN
                 end
    response = hit_cancel_esign_api(doc.provider_doc_id, auth_token)
    if response.success?
      # added transaction to avoid partial updates
      ActiveRecord::Base.transaction do
        doc.e_signatures.each do |esign|
          esign.add_api_update(response)
          esign.update(status: "cancelled", api_updates: esign.api_updates)
        end
        doc.update(esign_status: "cancelled")
      end
    else
      e = StandardError.new("Error cancelling #{doc.name} - #{response}")
      Rails.logger.error e.message
    end
  end

  # fetch manual updates from digio
  def update_esign_status(doc)
    if doc.esign_completed?
      # document already completed
      Rails.logger.debug { "Document #{doc.name} #{doc.id} already completed" }
    else
      auth_token = if doc.entity.entity_setting.digio_cutover_date.present? && doc.entity.entity_setting.digio_cutover_date < doc.sent_for_esign_date
                     doc.entity.entity_setting.digio_auth_token
                   else
                     AUTH_TOKEN
                   end
      # Get api response
      response = retrieve_signed(doc.provider_doc_id, auth_token)
      overall_status = JSON.parse(response.body)["status"].presence || JSON.parse(response.body)["agreement_status"] # can be "completed" or "requested"
      if response.success? && overall_status.present?
        # not updating to completed as check_and_update_document_status does it
        # if done here it wont download the signed document
        doc.update(esign_status: overall_status) unless overall_status.casecmp?("completed")
        # Update each esignature's status
        response['signing_parties'].each do |signer|
          # Find esignature for this email
          esign = doc.e_signatures.find_by(email: signer['identifier'])
          esign&.update_esign_response(signer['status'], response)
        end
        check_and_update_document_status(doc)
      else
        signatures_failed(doc, JSON.parse(response.body))
      end
    end
  end

  # handles Digio automatic callbacks
  def update_signature_progress(params)
    if params.dig('payload', 'document', 'id').present?
      if params.dig('payload', 'document', 'error_code').blank?
        process_esign_success(params)
      else
        process_esign_failure(params)
      end
    else
      e = StandardError.new("Document not found for #{params}")
      ExceptionNotifier.notify_exception(e)
      Rails.logger.error e.message
    end
  end

  private

  # used in digio callbacks
  def process_esign_success(params)
    provider_doc_id = params.dig('payload', 'document', 'id')
    doc = Document.find_by(provider_doc_id:)
    if doc.present?
      signing_parties = params.dig('payload', 'document', 'signing_parties')
      # update contains the statuses of all signing parties
      signing_parties.each do |signer|
        esign = doc.e_signatures.find_by(email: signer['identifier'])
        esign&.update_esign_response(signer['status'], params['payload'])
      end
      check_and_update_document_status(doc)
    else
      Rails.logger.error "Document not found for digio provider_doc_id #{provider_doc_id}"
    end
  end

  # used in digio callbacks
  def process_esign_failure(params)
    doc = Document.find_by(provider_doc_id: params.dig('payload', 'document', 'id'))
    email = params.dig('payload', 'document', 'signer_identifier')
    esign = doc.e_signatures.find_by(email:)
    esign&.update_esign_response("failed", params['payload'])
    ExceptionNotifier.notify_exception(StandardError.new("E-Sign not found for #{doc&.name} and email #{email} - #{params}")) if esign.blank?
  end

  def check_and_update_document_status(document)
    unsigned_esigns = document.e_signatures.reload.where.not(status: "signed")
    signature_completed(document) if unsigned_esigns.count < 1 && !document.esign_completed?
  end

  def signature_completed(doc)
    tmpfile = Tempfile.new("#{doc.name}.pdf", encoding: 'ascii-8bit')
    auth_token = if doc.entity.entity_setting.digio_cutover_date.present? && doc.entity.entity_setting.digio_cutover_date < doc.sent_for_esign_date
                   doc.entity.entity_setting.digio_auth_token
                 else
                   AUTH_TOKEN
                 end
    content = DigioEsignHelper.new.download(doc.provider_doc_id, auth_token).body
    tmpfile.write(content)
    doc.signature_completed(tmpfile.path)
    tmpfile.close
    tmpfile.unlink
  end

  def signatures_failed(doc, response)
    e = StandardError.new("Error getting status for #{doc.name} - #{response}")
    ExceptionNotifier.notify_exception(e)
    doc.update(esign_status: "failed")
    doc.e_signatures.each do |esign|
      esign.add_api_update(response)
      esign.save!
    end
    Rails.logger.error e.message
  end
end
