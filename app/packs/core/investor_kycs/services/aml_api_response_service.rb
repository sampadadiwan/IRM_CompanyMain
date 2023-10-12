class AmlApiResponseService
  DEFAULT_OPTIONS = {
    aml_entity_type: "person",
    fuzziness: "high",
    types: "all",
    birth_year: "",
    remove_deceased: true,
    country_codes: %w[IN US AE SG]
  }.freeze

  def get_response(name, options = {})
    aml_response = get_aml_response(name, options)
    json_response = get_json_response(aml_response)
    JSON.parse(json_response)
  end

  def get_aml_response(name, options = {})
    raise StandardError, "Name is required to generate AML Report!" if name.blank?

    aml_entity_type, fuzziness, types, birth_year, remove_deceased, country_codes = clean_options(options)

    url = URI(AmlReport::AML_URL)
    task_id = SecureRandom.uuid
    group_id = "#{task_id}-#{name}}"
    https = Net::HTTP.new(url.host, url.port)
    https.use_ssl = true
    request = Net::HTTP::Post.new(url)
    request["Content-Type"] = "application/json"
    # replace below with rails credentials
    request["api-key"] = Rails.application.credentials[:IDFY_API_KEY]
    request["account-id"] = Rails.application.credentials[:IDFY_ACCOUNT_ID]
    request.body = JSON.dump({
                               task_id:,
                               group_id:,
                               data: {
                                 search_term: name,
                                 fuzziness:,
                                 filters: {
                                   types:,
                                   birth_year:,
                                   remove_deceased:,
                                   country_codes:,
                                   entity_type: aml_entity_type
                                 }
                               }
                             })
    https.request(request)
  end

  def get_json_response(aml_response)
    response = JSON.parse(aml_response.read_body)
    url = response.dig('result', 'hits')
    if url.present?
      uri = URI(url)
      Net::HTTP.get(uri)
    else
      Rails.logger.info("No AML response found - #{response}")
      "{}"
    end
  end

  def clean_options(options)
    options = DEFAULT_OPTIONS.merge(options.symbolize_keys)
    aml_entity_type = options[:aml_entity_type]
    fuzziness = options[:fuzziness]
    types = options[:types]
    types = AmlReport.aml_types(types)
    birth_year = options[:birth_year]
    remove_deceased = options[:remove_deceased]
    country_codes = options[:country_codes]
    [aml_entity_type, fuzziness, types, birth_year, remove_deceased, country_codes]
  end
end
