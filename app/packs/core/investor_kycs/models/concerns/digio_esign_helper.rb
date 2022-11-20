require 'base64'

class DigioEsignHelper
  include HTTParty
  debug_output $stdout

  BASE_URL = ENV["DIGIO_BASE_URL"]
  AUTH_TOKEN = Base64.strict_encode64("#{ENV['DIGIO_CLIENT_ID']}:#{ENV['DIGIO_SECRET']}")

  def sign(name, email, phone, file_path, reason = "Adhaar eSing of document on CapHive")
    # Open the file you wish to encode
    data = File.read(file_path)

    # Encode the puppy
    encoded_file = Base64.strict_encode64(data)

    body = prepare_data(name, email, phone, encoded_file, reason)

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

  private

  def prepare_data(name, email, _phone, encoded_file, reason)
    {
      signers: [
        {
          identifier: email,
          name:,
          sign_type: "aadhaar",
          reason:
        }
        #   {
        #     "identifier": "<signer 2 email/mobile>",
        #     "name": "<Signer 2 Name>",
        #     "sign_type": "aadhaar",
        #     "reason": "<Reason for signing document>"
        #   }
      ],
      expire_in_days: 10,
      # "display_on_page": "custom",
      notify_signers: true,
      send_sign_link: true,
      file_name: "ToBeSigned.pdf",
      file_data: encoded_file
      # "sign_coordinates": {
      #   "<signer 1 email/mobile>": {
      #     "1": [
      #       {
      #         "llx": 380.5,
      #         "lly": 696.41,
      #         "urx": 540.81,
      #         "ury": 737.01
      #       }
      #     ],
      #     "2": [
      #       {
      #         "llx": 148.14,
      #         "lly": 784.73,
      #         "urx": 308.46,
      #         "ury": 825.33
      #       }
      #     ]
      #   },
      #   "<signer 2 email/mobile>": {
      #     "1": [
      #       {
      #         "llx": 398.76,
      #         "lly": 3.05,
      #         "urx": 559.08,
      #         "ury": 43.65
      #       }
      #     ],
      #     "2": [
      #       {
      #         "llx": 462.68,
      #         "lly": 207.09,
      #         "urx": 623,
      #         "ury": 247.7
      #       }
      #     ]
      #   }
      # },
      # "estamp_request": {
      #   "sign_on_page": "ALL",
      #   "note_content": "This is dummy content",
      #   "note_on_page": "ALL"
      # }
    }
  end
end
