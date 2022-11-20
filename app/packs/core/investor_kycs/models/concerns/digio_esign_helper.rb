require 'base64'

class DigioEsignHelper
  include HTTParty
  debug_output $stdout

  BASE_URL = ENV["DIGIO_BASE_URL"]
  AUTH_TOKEN = Base64.strict_encode64("#{ENV['DIGIO_CLIENT_ID']}:#{ENV['DIGIO_SECRET']}")

  def sign(user_ids, file_name, file_path, reason)
    # Open the file you wish to encode
    data = File.read(file_path)

    # Encode the puppy
    encoded_file = Base64.strict_encode64(data)

    body = prepare_data(user_ids, file_name, encoded_file, reason)

    response = HTTParty.post(
      "#{BASE_URL}/v2/client/document/uploadpdf",
      headers: {
        "authorization" => "Basic #{AUTH_TOKEN}",
        'Content-Type' => 'application/json'
      },
      body: body.to_json,
      debug_output: $stdout
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
      debug_output: $stdout
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
      debug_output: $stdout
    )

    Rails.logger.debug response

    response
  end

  #   private

  def prepare_data(user_ids, file_name, encoded_file, reason)
    {
      signers: prep_user_data(user_ids, reason),
      expire_in_days: 10,
      notify_signers: false,
      send_sign_link: false,
      file_name: file_name,
      file_data: encoded_file
    }
  end

  def prep_user_data(user_ids, reason)
    ret = []
    users = User.where(id: user_ids.split(","))
    users.each do |u|
      ret << {
        identifier: u.phone,
        name: u.full_name,
        sign_type: "aadhaar",
        reason:
      }
    end
    ret
  end
end
