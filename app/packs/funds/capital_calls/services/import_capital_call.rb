class ImportCapitalCall < ImportUtil
  STANDARD_HEADERS = ["Fund", "Name", "Percentage Called", "Due Date", "Call Date", "Fund Closes", "Generate Remittances", "Remittances Verified", "Call Basis", "Unit Price/Premium", "Send Call Notice", "Send Payment Notification"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def pre_process(ctx, import_upload:, **)
    super
    @exchange_rates = get_exchange_rates(ctx[:import_file], import_upload)
    true
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
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
        send_call_notice_flag = user_data["Send Call Notice"]&.downcase == "yes"
        send_payment_notification_flag = user_data["Send Payment Notification"]&.downcase == "yes"
        fund_closes = if user_data["Fund Closes"]
                        user_data["Fund Closes"].split(",").map(&:strip)
                      else
                        ["All"]
                      end
        percentage_called = user_data["Percentage Called"] || 0

        if fund_closes.include?("All")
          fund_closes = fund.capital_commitments.pluck(:fund_close)
          percentage_called = percentage_called.split(',').first.strip
          close_percentages = fund_closes.index_with { |_close| percentage_called }
          fund_closes = ["All"]
        else
          cleaned_fund_closes = fund_closes.map(&:strip)
          close_percentage_values = percentage_called.split(',').map(&:strip)
          close_percentages = cleaned_fund_closes.zip(close_percentage_values).to_h
        end

        # Make the capital_call
        capital_call = CapitalCall.new(entity_id: import_upload.entity_id, name:,
                                       fund:, due_date: user_data["Due Date"], call_date: user_data["Call Date"],
                                       import_upload_id: import_upload.id, fund_closes:,
                                       send_call_notice_flag:, close_percentages:,
                                       manual_generation: true, call_basis: user_data["Call Basis"],
                                       send_payment_notification_flag:, generate_remittances:, generate_remittances_verified:)
        setup_custom_fields(user_data, capital_call, custom_field_headers)

        check_exchange_rate(capital_call)

        setup_unit_prices(user_data, capital_call)

        result = CapitalCallCreate.call(capital_call:, import_upload:)
        raise result["errors"] unless result.success?

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
