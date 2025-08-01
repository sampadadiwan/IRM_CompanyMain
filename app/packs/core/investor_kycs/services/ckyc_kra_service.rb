# Service class to handle fetching and verifying CKYC/KRA data for Investor KYCs
class CkycKraService
  # Attempts to find existing CKYC data for an investor by PAN (and optionally phone).
  # If not found and 'create' is true, a new KYCData record is created and returned.
  def fetch_ckyc_data(investor_kyc, phone: nil, create: false)
    scope = investor_kyc.kyc_datas.ckyc.where(PAN: investor_kyc.PAN)
    scope = scope.where(phone: phone) if phone.present?
    ckyc_data = scope.last

    if ckyc_data.blank? && create
      ckyc_data = KycData.create(
        entity: investor_kyc.entity,
        investor_kyc: investor_kyc,
        PAN: investor_kyc.PAN,
        birth_date: investor_kyc.birth_date,
        source: :ckyc,
        phone: phone
      )
    end

    ckyc_data
  end

  # Similar to fetch_ckyc_data but for KRA.
  # Uses both PAN and birth_date as filters (phone optional).
  # Returns existing or newly created KYCData.
  def fetch_kra_data(investor_kyc, phone: nil, create: false)
    return if investor_kyc.birth_date.blank?

    scope = investor_kyc.kyc_datas.kra.where(PAN: investor_kyc.PAN, birth_date: investor_kyc.birth_date)
    scope = scope.where(phone: phone) if phone.present?
    kra_data = scope.last

    if kra_data.blank? && create
      kra_data = KycData.create(
        entity: investor_kyc.entity,
        investor_kyc: investor_kyc,
        PAN: investor_kyc.PAN,
        birth_date: investor_kyc.birth_date,
        source: :kra,
        phone: phone
      )
    end

    kra_data
  end

  # Step 1: Searches CKYC using PAN/DOB.
  # If found, saves CKYC number and triggers OTP sending.
  # Returns success status, message, and request_id (if OTP sent).
  def search_ckyc_data_and_send_otp(ckyc_data)
    response = KycVerify.new.search_ckyc(ckyc_data)

    unless response["success"]
      log_ckyc_failure(ckyc_data, response, "Not Found")
      return [false, "CKYC Data not found for #{ckyc_data.PAN}. Error: #{response['error_message']}", nil]
    end

    # Extract CKYC number from last result and save it
    ckyc_number = response.dig("search_results", -1, "ckyc_number")
    ckyc_data.update(external_identifier: ckyc_number)

    send_ckyc_otp(ckyc_data)
  rescue StandardError => e
    msg = "Failed to search CKYC Data for PAN: #{ckyc_data.PAN}. Error: #{e.message}"
    Rails.logger.error(msg)
    [false, msg, nil]
  end

  # Step 2: Sends OTP to mobile number associated with CKYC record
  def send_ckyc_otp(ckyc_data)
    response = KycVerify.new.send_otp(ckyc_data)

    unless response["success"]
      log_ckyc_failure(ckyc_data, response, "Send OTP Failed")
      return [false, "Failed to send OTP for CKYC number #{ckyc_data.phone}. Error: #{response['error_message']}", nil]
    end

    ckyc_data.update(status: "OTP Sent")
    [true, response["message"], response["request_id"]]
  rescue StandardError => e
    msg = "Failed to send CKYC OTP for PAN: #{ckyc_data.PAN}. Error: #{e.message}"
    Rails.logger.error(msg)
    [false, msg, nil]
  end

  # Step 3: Uses OTP and request ID to fetch CKYC data
  def get_ckyc_data(otp, ckyc_data, request_id)
    response = KycVerify.new.download_ckyc_response(otp, ckyc_data, request_id)

    unless response["success"]
      log_ckyc_failure(ckyc_data, response, "Failed")
      return [false, "Failed to fetch CKYC data. Error: #{response['error_message']}"]
    end

    ckyc_data.update(status: "Success", response: response)
    [true, "CKYC Data found for PAN: #{ckyc_data.PAN}"]
  rescue StandardError => e
    msg = "Exception in get_ckyc_data for PAN: #{ckyc_data.PAN}. Error: #{e.message}"
    Rails.logger.error(msg)
    [false, msg]
  end

  # Fetches KRA data via PAN and verifies it
  def get_kra_data(kra_data)
    response = KycVerify.new.get_kra_pan_response(kra_data)
    status_desc = response.dig("kyc_information", "status_description")

    if status_desc&.include?("KYC details have been successfully verified")
      kra_data.update(status: "Success", response: response)
      [true, "KRA Data found for PAN: #{kra_data.PAN}"]
    else
      log_kra_failure(kra_data, response)
      [false, "KRA Data not found. Error: #{response['error']}"]
    end
  rescue StandardError => e
    msg = "Exception in get_kra_data for PAN: #{kra_data.PAN}. Error: #{e.message}"
    Rails.logger.error(msg)
    [false, msg]
  end

  private

  # Logs CKYC failure and updates status in the DB
  def log_ckyc_failure(ckyc_data, response, status)
    msg = response["error_message"] || "Unknown error"
    Rails.logger.error("CKYC Error: #{msg}")
    Rails.logger.debug { "CKYC Response: #{response}" }
    ckyc_data.update(status: status)
  end

  # Logs KRA failure and updates status in the DB
  def log_kra_failure(kra_data, response)
    msg = response["error"] || "Unknown error"
    Rails.logger.error("KRA Error: #{msg}")
    Rails.logger.debug { "KRA Response: #{response}" }
    kra_data.update(status: "Failed")
  end
end
