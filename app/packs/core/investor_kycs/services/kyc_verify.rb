class KycVerify
  include HTTParty

  debug_output $stdout

  BASE_URL = ENV.fetch("DIGIO_BASE_URL", nil)
  AUTH_TOKEN = Base64.strict_encode64("#{Rails.application.credentials[:DIGIO_CLIENT_ID]}:#{Rails.application.credentials[:DIGIO_SECRET]}")

  def verify_pan_exists(pan)
    HTTParty.post(
      "#{BASE_URL}/v3/client/kyc/fetch_id_data/PAN",
      headers: {
        "authorization" => "Basic #{AUTH_TOKEN}",
        'Content-Type' => 'application/json'
      },
      body: {
        id_no: pan,
        unique_request_id: SecureRandom.hex(5)
      }.to_json,
      debug_output: Rails.env.development? ? $stdout : nil
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
          unique_request_id: SecureRandom.hex(5),
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
        verified: resp["pan_verification_response"]["verified"]
      }
    else
      { status: "failed", resp: }
    end
  end

  #   {"id"=>"DC8GII9WMEGVJ9K",
  #  "verified"=>true,
  #  "verified_at"=>"2022-12-05 11:19:35",
  #  "beneficiary_name_with_bank"=>"THIMMAIAH C",
  #  "fuzzy_match_result"=>true,
  #  "fuzzy_match_score"=>88}

  def verify_bank(full_name, account_number, ifsc)
    HTTParty.post(
      "#{BASE_URL}/client/verify/bank_account",
      headers: {
        "authorization" => "Basic #{AUTH_TOKEN}",
        'Content-Type' => 'application/json'
      },
      body: {
        unique_request_id: SecureRandom.hex(5),
        beneficiary_account_no: account_number,
        beneficiary_ifsc: ifsc,
        beneficiary_name: full_name
      }.to_json
    )
  end

  def search_ckyc(fi_code, pan)
    # onve digio's staging ckyc api is up, we roll this back
    base_url = ENV.fetch("DIGIO_BASE_URL_PROD", nil)
    auth_token = Base64.strict_encode64("#{Rails.application.credentials[:DIGIO_CLIENT_ID_PROD]}:#{Rails.application.credentials[:DIGIO_SECRET_PROD]}")
    if Rails.env.production?
      base_url = BASE_URL
      auth_token = AUTH_TOKEN
    end
    HTTParty.post(
      "#{base_url}/v3/client/kyc/ckyc/search",
      headers: {
        "authorization" => "Basic #{auth_token}",
        'Content-Type' => 'application/json'
      },

      body: {
        id_no: pan,
        fi_code:,
        unique_request_id: SecureRandom.hex(5)
      }.to_json
    )
  end

  def download_ckyc_response(ckyc_number, fi_code, birth_date)
    base_url = ENV.fetch("DIGIO_BASE_URL_PROD", nil)
    auth_token = Base64.strict_encode64("#{Rails.application.credentials[:DIGIO_CLIENT_ID_PROD]}:#{Rails.application.credentials[:DIGIO_SECRET_PROD]}")
    if Rails.env.production?
      base_url = BASE_URL
      auth_token = AUTH_TOKEN
    end
    downloaded_response = HTTParty.post(
      "#{base_url}/v3/client/kyc/ckyc/download",
      headers: {
        "authorization" => "Basic #{auth_token}",
        'Content-Type' => 'application/json'
      },

      body: {
        ckyc_no: ckyc_number,
        date_of_birth: birth_date, # dd-MM-yyyy format
        fi_code:,
        unique_request_id: SecureRandom.hex(5)
      }.to_json
    )
    ckyc_response = downloaded_response.parsed_response
    Rails.logger.error("CKYC data not found. Error: #{ckyc_response['error']}") if ckyc_response["success"] == false
    ckyc_response
  end

  def get_kra_pan_response(pan, dob)
    downloaded_response = HTTParty.post(
      "#{BASE_URL}/v3/client/kyc/kra/get_pan_details",
      headers: {
        "authorization" => "Basic #{AUTH_TOKEN}",
        'Content-Type' => 'application/json'
      },

      body: {
        pan_no: pan,
        dob: dob&.strftime("%m/%d/%Y"), # DD/MM/YYYY format
        unique_request_id: SecureRandom.hex(5)
      }.to_json
    )
    kra_response = downloaded_response.parsed_response
    Rails.logger.error("KRA data not found. Error: #{kra_response['error']}") if kra_response["result"] != "FOUND"
    kra_response
  end
end
