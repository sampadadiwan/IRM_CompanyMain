require 'base64'

class AdhaarEsign
  include HTTParty
  debug_output $stdout

  def sign(name, email, phone, file_path)
    # Open the file you wish to encode
    data = File.read(file_path)

    # Encode the puppy
    encoded_file = Base64.encode64(data)

    data = prepare_data(name, email, phone, encoded_file)

    response = HTTParty.post(
      'https://eve.idfy.com/v3/tasks/sync/generate/esign_document',
      headers: {
        "api-key" => ENV["IDFY_API_KEY"],
        "account-id" => ENV["IDFY_ACCOUNT_ID"],
        'Content-Type' => 'application/json'
      },
      'data-raw': {
        task_id: rand(5**5),
        group_id: "KYC_ESIGN",
        data:
      },
      debug_output: $stdout
    )

    Rails.logger.debug response
  end

  private

  def prepare_data(name, email, phone, encoded_file)
    {
      flow_type: "pdf",
      user_key: "M0OG222aTkaAJo8ATSa4cJkIIpvFXvP0",
      verify_aadhaar_details: true,
      esign_file_details: {
        esign_profile_id: "iIxiRbr",
        file_name: "sample pdf",
        esign_file: encoded_file,
        esign_allow_fill: false
      },

      esign_invitees: [
        {
          esigner_name: name,
          esigner_email: email,
          esigner_phone: phone,
          aadhaar_esign_verification: {
            aadhaar_pincode: "",
            aadhaar_yob: "",
            aadhaar_gender: ""
          }

        }

      ]
    }
  end
end
