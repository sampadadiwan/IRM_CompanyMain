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
    tmpfile.unlink
    # fetch from esign
    display_on_page = document.display_on_page&.downcase || "last"
    body = prepare_data(document, document.name, encoded_file, display_on_page)

    response = HTTParty.post(
      "#{BASE_URL}/v2/client/document/uploadpdf",
      headers: {
        "authorization" => "Basic #{AUTH_TOKEN}",
        'Content-Type' => 'application/json'
      },
      body: body.to_json,
      debug_output: @debug ? $stdout : nil
    )

    Rails.logger.debug response
    response
  end

  def retrieve_signed(esign_doc_id)
    response = HTTParty.get(
      "#{BASE_URL}/v2/client/document/#{esign_doc_id}",
      headers: {
        "authorization" => "Basic #{AUTH_TOKEN}",
        'Content-Type' => 'application/json'
      },
      debug_output: @debug ? $stdout : nil
    )

    Rails.logger.debug response

    response
  end

  def download(esign_doc_id)
    response = HTTParty.get(
      "#{BASE_URL}/v2/client/document/download?document_id=#{esign_doc_id}",
      headers: {
        "authorization" => "Basic #{AUTH_TOKEN}",
        'Content-Type' => 'application/json'
      },
      debug_output: @debug ? $stdout : nil
    )

    Rails.logger.debug response

    response
  end

  #   private

  def prepare_data(doc, file_name, encoded_file, display_on_page = "last")
    {
      signers: prep_user_data(doc.e_signatures),
      expire_in_days: 10,
      notify_signers: true,
      send_sign_link: true,
      # true only needed for widget
      generate_access_token: false,
      display_on_page:,
      file_name:,
      file_data: encoded_file
    }
  end

  def prep_user_data(esigns)
    ret = []
    esigns.order(:position).each do |esign|
      u = esign.user
      sign_type = esign.signature_type.downcase || "aadhaar"
      reason = nil # fetch from esign or doc
      hash = {
        identifier: u.email,
        name: u.full_name,
        sign_type:
      }
      hash[:reason] = reason if reason.present?
      ret << hash
    end
    ret
  end
end
