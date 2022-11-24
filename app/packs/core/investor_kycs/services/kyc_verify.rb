class KycVerify
  include HTTParty
  debug_output $stdout

  BASE_URL = ENV["DIGIO_BASE_URL"]
  AUTH_TOKEN = Base64.strict_encode64("#{ENV['DIGIO_CLIENT_ID']}:#{ENV['DIGIO_SECRET']}")

  def verify_pan_exists(pan)
    HTTParty.post(
      "#{BASE_URL}/v3/client/kyc/fetch_id_data/PAN",
      headers: {
        "authorization" => "Basic #{AUTH_TOKEN}",
        'Content-Type' => 'application/json'
      },
      body: {
        id_no: pan
      }.to_json,
      debug_output: $stdout
    )
  end

  def verify_pan_card(file)
    file.download do |tmp_file|
      file_path = tmp_file.path
      resp = HTTParty.post(
        "#{BASE_URL}/v3/client/kyc/analyze/file/idcard",
        headers: {
          "authorization" => "Basic #{AUTH_TOKEN}",
          'Content-Type' => 'multipart/form-data'
        },

        body: {
          unique_request_id: rand(5**5),
          front_part: File.new(file_path),
          should_verify: "true"
        }
      )
      generate_response(resp)
    end
  end

  def generate_response(resp)
    if resp.success?
      {
        status: "success",
        fathers_name: resp["fathers_name"],
        name: resp["name"],
        dob: resp["dob"],
        id_no: resp["id_no"],
        is_pan_dob_valid: resp["pan_verification_response"]["is_pan_dob_valid"],
        name_matched: resp["pan_verification_response"]["name_matched"],
        verified: resp["id_card_verification_response"]["verified"]
      }
    else
      { status: "failed", resp: }
    end
  end

  def verify_bank(full_name, account_number, ifsc)
    HTTParty.post(
      "#{BASE_URL}/client/verify/bank_account",
      headers: {
        "authorization" => "Basic #{AUTH_TOKEN}",
        'Content-Type' => 'application/json'
      },
      body: {
        beneficiary_account_no: account_number,
        beneficiary_ifsc: ifsc,
        beneficiary_name: full_name
      }.to_json
    )
  end
end
