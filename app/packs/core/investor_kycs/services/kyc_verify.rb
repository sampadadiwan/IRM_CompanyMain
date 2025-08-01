class KycVerify
  include HTTParty

  debug_output $stdout

  BASE_URL = ENV.fetch("DIGIO_BASE_URL", nil)
  AUTH_TOKEN = Base64.strict_encode64("#{Rails.application.credentials[:DIGIO_CLIENT_ID]}:#{Rails.application.credentials[:DIGIO_SECRET]}")

  def verify_pan_exists(pan, kyc_data)
    response = api_verify_pan_exists(pan)
    json_response = JSON.parse(response.body)
    store_kyc_data(kyc_data, json_response)
    json_response
  end

  def verify_bank(full_name, account_number, ifsc, kyc_data)
    response = api_verify_bank(full_name, account_number, ifsc)
    json_response = JSON.parse(response.body)
    store_kyc_data(kyc_data, json_response)
    json_response
  end

  def verify_pan_card(file)
    file.download do |tmp_file|
      file_path = tmp_file.path
      response = api_verify_pan_card(file_path)
      JSON.parse(response.body)
    end
  end

  # This API is hit first in the CKYC flow
  # Response contains the CKYC Reference ID and other details
  def search_ckyc(ckyc_data)
    pan = ckyc_data.PAN
    fi_code = ckyc_data.entity.entity_setting.fi_code

    request_body = {
      id_type: "PAN",
      id_no: pan,
      fi_code: fi_code,
      unique_request_id: SecureRandom.hex(10)
    }

    response = api_search_ckyc(request_body)
    json_response = JSON.parse(response.body)
    store_kyc_data(ckyc_data, json_response, request: request_body)
    json_response
  end

  # This API is hit after successful CKYC search
  # It sends an OTP to the registered mobile number for the CKYC number
  # The response contains the request ID which is used to download the CKYC data
  # If the mobile number is not registered, it returns an error
  def send_otp(ckyc_data)
    request_body = {
      ckyc_number: ckyc_data.external_identifier,
      fi_code: ckyc_data.entity.entity_setting.fi_code,
      unique_request_id: SecureRandom.hex(10),
      auth_factor_type: "MOBILE_NO",
      auth_factor_value: ckyc_data.phone
    }

    response = api_send_otp(request_body)
    json_response = JSON.parse(response.body)
    store_kyc_data(ckyc_data, json_response, request: request_body)
    json_response
  end

  # This API is hit after sending the OTP
  # It downloads the CKYC data using the OTP and request ID
  def download_ckyc_response(otp, ckyc_data, request_id)
    request_body = {
      otp: otp,
      dateTime: Time.zone.now.strftime("%d-%m-%Y %H:%M:%S"),
      validate: true,
      fi_code: ckyc_data.entity.entity_setting.fi_code,
      request_id: request_id
    }

    response = api_download_ckyc_response(request_body)
    json_response = JSON.parse(response.body)
    store_kyc_data(ckyc_data, json_response, request: request_body)
    Rails.logger.error("CKYC data not found. Error: #{json_response['error']}") if json_response["success"] == false
    json_response
  end

  # API to fetch KRA details using PAN and DOB
  def get_kra_pan_response(kra_data)
    request_body = {
      pan_no: kra_data.PAN,
      dob: kra_data.birth_date&.strftime("%m/%d/%Y"),
      unique_request_id: SecureRandom.hex(10)
    }

    response = api_get_kra_pan_response(request_body)
    json_response = JSON.parse(response.body)
    store_kyc_data(kra_data, json_response, request: request_body)
    json_response
  end

  private

  def auth_headers_json
    {
      "authorization" => "Basic #{AUTH_TOKEN}",
      "Content-Type" => "application/json"
    }
  end

  def auth_headers_multipart
    {
      "authorization" => "Basic #{AUTH_TOKEN}",
      "Content-Type" => "multipart/form-data"
    }
  end

  def digio_credentials
    if Rails.env.production?
      [BASE_URL, AUTH_TOKEN]
    else
      base_url = ENV.fetch("DIGIO_BASE_URL_PROD", nil)
      auth_token = Base64.strict_encode64("#{Rails.application.credentials[:DIGIO_CLIENT_ID_PROD]}:#{Rails.application.credentials[:DIGIO_SECRET_PROD]}")
      [base_url, auth_token]
    end
  end

  # Stores the request and response data in the KYC data object
  def store_kyc_data(kyc_data, response, request: nil)
    now = Time.zone.now
    kyc_data.request_data ||= {}
    kyc_data.response_data ||= {}
    kyc_data.request_data[now] = request if request
    kyc_data.response_data[now] = response
  end

  # API methods below

  def api_verify_pan_exists(pan)
    HTTParty.post("#{BASE_URL}/v3/client/kyc/fetch_id_data/PAN", headers: auth_headers_json, body: { id_no: pan, unique_request_id: SecureRandom.hex(10) }.to_json)
  end

  def api_verify_pan_card(file_path)
    HTTParty.post("#{BASE_URL}/v3/client/kyc/analyze/file/idcard", headers: auth_headers_multipart, body: { unique_request_id: SecureRandom.hex(10), front_part: File.new(file_path), should_verify: "true" })
  end

  def api_verify_bank(full_name, account_number, ifsc)
    HTTParty.post("#{BASE_URL}/client/verify/bank_account", headers: auth_headers_json, body: { unique_request_id: SecureRandom.hex(10), beneficiary_account_no: account_number, beneficiary_ifsc: ifsc, beneficiary_name: full_name }.to_json)
  end

  def api_search_ckyc(request_body)
    base_url, auth_token = digio_credentials
    HTTParty.post("#{base_url}/v3/client/kyc/ckyc/search", headers: { "authorization" => "Basic #{auth_token}", 'Content-Type' => 'application/json' }, body: request_body.to_json)
  end

  def api_send_otp(request_body)
    base_url, auth_token = digio_credentials
    HTTParty.post("#{base_url}/v3/client/kyc/ckyc/get_otp", headers: { "authorization" => "Basic #{auth_token}", 'Content-Type' => 'application/json' }, body: request_body.to_json)
  end

  def api_download_ckyc_response(request_body)
    base_url, auth_token = digio_credentials
    HTTParty.post("#{base_url}/v3/client/kyc/ckyc/download", headers: { "authorization" => "Basic #{auth_token}", 'Content-Type' => 'application/json' }, body: request_body.to_json)
  end

  def api_get_kra_pan_response(request_body)
    HTTParty.post("#{BASE_URL}/v3/client/kyc/kra/get_pan_details", headers: auth_headers_json, body: request_body.to_json)
  end
end
