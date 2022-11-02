require 'base64'

class AdhaarEsign
  include HTTParty
  debug_output $stdout

  def sign(name, email, phone, file_path)
    # Open the file you wish to encode
    data = File.read(file_path)

    # Encode the puppy
    encoded_file = Base64.strict_encode64(data)

    data = prepare_data(name, email, phone, encoded_file)

    response = HTTParty.post(
      'https://eve.idfystaging.com/v3/tasks/sync/generate/esign_document',
      headers: {
        "api-key" => '9f81f27e-f5e1-4eae-b3ae-131e0101ea7e', # ENV["IDFY_API_KEY"],
        # "account-id" => ENV["IDFY_ACCOUNT_ID"],
        'Content-Type' => 'application/json'
      },
      body: {
        task_id: rand(5**5).to_s,
        group_id: "ADHAAR_ESIGN",
        data:
      }.to_json,
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
        file_name: "Test.pdf",
        esign_file: encoded_file.to_s,
        esign_allow_fill: false
      },

      esign_invitees: [
        {
          esigner_name: name.to_s,
          esigner_email: email.to_s,
          esigner_phone: phone.to_s,
          aadhaar_esign_verification: {
            aadhaar_pincode: "560035",
            aadhaar_yob: "1975",
            aadhaar_gender: "Male"
          }

        }

      ]
    }
  end
end
