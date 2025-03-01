class AmlApiResponseService
  AML_URL = "https://api.idfy.com/v3/tasks/async/verify_with_source/aml".freeze
  GET_TASK_URL = "https://eve.idfy.com/v3/tasks?request_id=".freeze

  def get_response(aml_report_object)
    body = get_request_body(aml_report_object.investor_kyc.full_name, aml_report_object.investor_kyc.PAN, aml_report_object.investor_kyc.birth_date)
    aml_response = get_async_response(body)
    initial_response = JSON.parse(aml_response.read_body)

    aml_report_object.request_data ||= {}
    aml_report_object.request_data[Time.zone.now.to_s] = body
    aml_report_object.response_data ||= {}
    aml_report_object.response_data[Time.zone.now.to_s] = initial_response
    aml_report_object.save!
  end

  def get_report(aml_report_object)
    request_id = nil
    if aml_report_object.response_data.present?
      last_response = aml_report_object.response_data[aml_report_object.response_data.keys.last]
      if last_response.instance_of?(Hash)
        request_id = last_response["request_id"]
      elsif last_response.instance_of?(Array)
        request_id = last_response.first["request_id"]
      end
    end
    report_response = get_report_response(request_id)
    json_res = JSON.parse(report_response.read_body)
    aml_report_object.response_data[Time.zone.now.to_s] = json_res
    aml_report_object.save!
    json_res
  end

  def get_report_response(request_id)
    url = URI("https://eve.idfy.com/v3/tasks?request_id=#{request_id}")
    https = Net::HTTP.new(url.host, url.port)
    https.use_ssl = true
    request = Net::HTTP::Get.new(url)
    request["api-key"] = Rails.application.credentials[:IDFY_API_KEY]
    request["account-id"] = Rails.application.credentials[:IDFY_ACCOUNT_ID]
    request["Content-Type"] = "application/json"
    https.request(request)
  end

  def get_async_response(body)
    url = URI(AML_URL)
    https = Net::HTTP.new(url.host, url.port)
    https.use_ssl = true
    request = Net::HTTP::Post.new(url)
    request["Content-Type"] = "application/json"
    request["api-key"] = Rails.application.credentials[:IDFY_API_KEY]
    request["account-id"] = Rails.application.credentials[:IDFY_ACCOUNT_ID]
    request.body = body
    https.request(request)
  end

  def get_request_body(name, pan, dob)
    raise StandardError, "Name is required to generate AML Report!" if name.blank?

    data = {
      task_id: SecureRandom.uuid,
      group_id: SecureRandom.uuid,
      data: {
        search_term: name.strip,
        filters: {
          # birth_year: nil,
          # birth_year_fuzziness: "2",
          # search_profile: "",
          name_fuzziness: "2",
          types: %w[sanctions pep warnings adverse_media],
          # pan_number: nil,
          entity_type: "individual"
        },
        get_profile_pdf: true,
        cibil_check: false, # confirm with template
        version: "2"
      }
    }
    data[:data][:filters][:pan_number] = pan if pan.present?

    # if dob.present?
    year = dob.present? ? dob.year.to_s : "1900" # added as api gives error if this is not passed
    data[:data][:filters][:birth_year] = year
    data[:data][:filters][:birth_year_fuzziness] = "2"
    # end
    data.to_json
  end
end
