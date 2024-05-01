class ImportCapitalCall < ImportUtil
  STANDARD_HEADERS = ["Fund", "Name", "Percentage Called", "Due Date", "Call Date", "Fund Closes", "Generate Remittances", "Remittances Verified", "Type", "Call Basis", "Unit Price/Premium"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def pre_process(ctx, import_upload:, **)
    super(ctx, import_upload:, **)
    @exchange_rates = get_exchange_rates(ctx[:import_file], import_upload)
    true
  end

  def save_row(user_data, import_upload, custom_field_headers)
    Rails.logger.debug { "Processing capital_call #{user_data}" }

    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"]).first

    if fund
      name = user_data["Name"]
      if CapitalCall.exists?(entity_id: import_upload.entity_id, fund:, name:)
        raise "Capital Call Already Present"
      else
        generate_remittances = user_data["Generate Remittances"]&.downcase == "yes"
        generate_remittances_verified = user_data["Remittances Verified"]&.downcase == "yes"
        fund_closes = user_data["Fund Closes"] ? user_data["Fund Closes"].split(",") : ["All"]

        # Make the capital_call
        capital_call = CapitalCall.new(entity_id: import_upload.entity_id, name:,
                                       fund:, due_date: user_data["Due Date"],
                                       call_date: user_data["Call Date"],
                                       fund_closes:, commitment_type: user_data["Type"],
                                       percentage_called: user_data["Percentage Called"],
                                       manual_generation: true, call_basis: user_data["Call Basis"],
                                       import_upload_id: import_upload.id,
                                       generate_remittances:, generate_remittances_verified:)

        setup_custom_fields(user_data, capital_call, custom_field_headers)

        check_exchange_rate(capital_call)

        setup_unit_prices(user_data, capital_call)

        result = CapitalCallCreate.call(capital_call:, import_upload:)
        raise result["errors"].full_messages.join(",") unless result.success?

        result.success?
      end
    else
      raise "Fund not found"
    end
  end

  def setup_unit_prices(user_data, capital_call)
    # Setup the unit prices specified as unit_type_1:price:premium,unit_type_2:price:premium
    unit_price_premium = user_data["Unit Price/Premium"]&.split(",")&.map(&:strip)
    if unit_price_premium.present?
      unit_price_premium.each do |upp|
        unit_type, price, premium = upp.split(":").map(&:strip)
        raise("Unit Type #{unit_type} not found in Fund") unless capital_call.fund.unit_types_list.include?(unit_type)

        capital_call.unit_prices ||= {}
        capital_call.unit_prices[unit_type] = { price:, premium: }.stringify_keys
      end
    end
  end

  # Capital call imports a re special, they have a special sheet called Exchange Rates in the XL
  # This sheet must specify the exchange rate for the call_date for a multicurrency fund
  # These rates are created before the call is created, so that the commitment amounts get adjusted
  # due to the exchange_rate
  def check_exchange_rate(capital_call)
    # We need to setup the commitments for the exchange rate
    er_user_data = @exchange_rates.filter { |er| er["As Of"] == capital_call.call_date }
    if er_user_data.present?
      er_user_data.each do |erud|
        exchange_rate = setup_exchange_rate(capital_call, erud)
        Rails.logger.debug { "Created #{exchange_rate}" }
      end
    else
      Rails.logger.debug { "No ExchangeRate specified for Call #{capital_call}" }
    end
  end

end
