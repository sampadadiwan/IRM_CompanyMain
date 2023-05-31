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
        id_no: pan
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
        beneficiary_account_no: account_number,
        beneficiary_ifsc: ifsc,
        beneficiary_name: full_name
      }.to_json
    )
  end

  def search_ckyc(fi_code, pan)
    HTTParty.post(
      "#{BASE_URL}/v3/client/kyc/ckyc/search",
      headers: {
        "authorization" => "Basic #{AUTH_TOKEN}",
        'Content-Type' => 'application/json'
      },

      body: {
        id_no: pan,
        fi_code:,
        unique_request_id: rand(5**5)
      }.to_json
    )
  end

  def download_ckyc_response(_search_ckyc_parsed_response, _fi_code, _birth_date)
    # downloaded_response = HTTParty.post(
    #   "#{BASE_URL}/v3/client/kyc/ckyc/download",
    #   headers: {
    #     "authorization" => "Basic #{AUTH_TOKEN}",
    #     'Content-Type' => 'application/json'
    #   },

    #   body: {
    #     ckyc_no: search_ckyc_parsed_response["ckyc_number"],
    #     date_of_birth: birth_date&.strftime("%m-%d-%Y"), # dd-MM-yyyy format
    #     fi_code:,
    #     unique_request_id: rand(5**5)
    #   }.to_json
    # )
    # ckyc_response = downloaded_response.parsed_response
    # dont commit below
    ckyc_response = sample_ckyc_download_response
    Rails.logger.error("CKYC data not found. Error: #{ckyc_response['error']}") if ckyc_response["success"] == false
    ckyc_response
  end

  def get_kra_pan_response(_pan, _dob)
    # downloaded_response = HTTParty.post(
    #   "#{BASE_URL}/v3/client/kyc/kra/get_pan_details",
    #   headers: {
    #     "authorization" => "Basic #{AUTH_TOKEN}",
    #     'Content-Type' => 'application/json'
    #   },

    #   body: {
    #     pan_no: pan,
    #     dob: dob&.strftime("%m/%d/%Y"), # DD/MM/YYYY format
    #     unique_request_id: rand(5**5)
    #   }.to_json
    # )
    # kra_response = downloaded_response.parsed_response
    kra_response = sample_kra_pan_data
    Rails.logger.error("KRA data not found. Error: #{kra_response['error']}") if kra_response["result"] != "FOUND"
    kra_response
  end

  def sample_ckyc_search_response
    {
      success: true,
      search_response: {
        ckyc_number: "{CKYC Number Here}",
        name: "MR DINESH  RATHORE ",
        fathers_name: "Mr TEJA  RAM RATHORE",
        age: "30",
        image_type: "jpg",
        photo: "{Base64 Value of Image}",
        kyc_date: "08-04-2017",
        updated_date: "08-04-2017",
        remarks: ""
      }
    }
  end

  def sample_err_response
    {
      success: false,
      error_message: "{Error Message}"
    }
  end

  def sample_ckyc_download_response
    {
      success: true,
      download_response: {
        personal_details: {
          ckyc_number: Faker::Number.number(digits: 12), type: "INDIVIDUAL/CORP/HUF etc", kyc_type: "normal/ekyc/minor", prefix: "MR", first_name: Faker::Name.first_name, middle_name: Faker::Name.middle_name, last_name: Faker::Name.last_name, full_name: Faker::Name.name, maiden_prefix: "", maiden_first_name: "", maiden_middle_name: "", maiden_last_name: "", maiden_full_name: "", father_spouse_flag: "father/spouse", father_prefix: "Mr", father_first_name: "TEJA", father_middle_name: "", father_last_name: "RAM RATHORE", father_full_name: "Mr TEJA  RAM RATHORE", mother_prefix: "Mrs", mother_first_name: "", mother_middle_name: "", mother_last_name: "", mother_full_name: "", gender: "M", dob: "{}", pan: Faker::Number.number(digits: 10), perm_address_line1: "BERA NAVODA", perm_address_line2: "BER KALAN", perm_address_line3: "JAITARAN", perm_address_city: "JAITARAN", perm_address_dist: "Pali", perm_address_state: "RJ", perm_address_country: "IN", perm_address_pincode: "306302", perm_current_same: "Y/N", corr_address_line1: "BERA NAVODA", corr_address_line2: "BER KALAN", corr_address_line3: "JAITARAN", corr_address_city: "JAITARAN", corr_address_dist: "Pali", corr_address_state: "RJ", corr_address_country: "IN", corr_address_pincode: "306302", mobile_no: Faker::Number.number(digits: 10), email: Faker::Internet.email, date: "02-04-2017", place: "Bangalore"
        },
        id_details: [
          {
            type: "PAN", id_no: Faker::Number.number(digits: 10), ver_status: true
          }
        ],
        images: [
          {
            image_type: "PHOTO", type: "jpg/pdf", data: Base64.strict_encode64(File.read("public/img/logo_big.png"))
          },
          {
            image_type: "PAN", type: "jpg/pdf", data: Base64.encode64(File.read("public/img/whatsappQR.png"))
          },
          {
            image_type: "AADHAAR/PASSPORT/VOTER/DL", type: "jpg/pdf", data: "{BASE64}"
          },
          {
            image_type: "SIGNATURE", type: "jpg/pdf", data: "{BASE64}"
          }
        ]
      }
    }
  end

  def sample_kra_pan_data
    {
      result: "FOUND",
      pan_number: Faker::Number.number(digits: 10),
      name: Faker::Name.name,
      status: "KRA Verified",
      status_date: "29-04-2017 16:16:45",
      entry_date: "12-04-2017 12:30:16",
      modification_date: "",
      kyc_mode: "Normal KYC",
      deactivate_remarks: "",
      update_remarks: "",
      ipv_flag: "Y",
      pan_details: {
        pan_number: Faker::Number.number(digits: 10), dob: "05/07/1990", gender: "M", name: Faker::Name.name, father_name: Faker::Name.name, correspondence_address1: "", correspondence_address2: "", correspondence_address3: "JAITARAN", correspondence_city: "PALI", correspondence_pincode: "306302", correspondence_state: "Rajasthan", correspondence_country: "India", correspondence_address_proof: "Id Type", correspondence_address_proof_ref: "Id Number", correspondence_address_proof_date: "",
        mobile_number: Faker::Number.number(digits: 10),
        email_address: Faker::Internet.email, permanent_address1: "", permanent_address2: "", permanent_address3: "JAITARAN", permanent_city: "PALI", permanent_pincode: "306302", permanent_state: "Rajasthan", permanent_country: "India", permanent_address_proof: "Id type", permanent_address_proof_ref: "Id Number", permanent_address_proof_date: "", income: "> 25 LAC", occupation: "PRIVATE SECTOR SERVICE", political_connection: "NA", resident_status: "R", nationality: "Indian", ipv_date: "29/03/2017"
      }
    }
  end
end
