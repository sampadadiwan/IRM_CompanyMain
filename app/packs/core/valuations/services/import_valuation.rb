class ImportValuation < ImportUtil
  STANDARD_HEADERS = ["Instrument", "Valuation Date", "Valuation", "Per Share Value", "Portfolio Company"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    # puts "processing #{user_data}"
    valuation_date = user_data['Valuation Date']
    valuation_cents = user_data['Valuation'].to_d * 100
    per_share_value_cents = user_data['Per Share Value'].to_d * 100
    investor_name = user_data['Portfolio Company']
    instrument_name = user_data['Instrument']
    entity = import_upload.entity

    investor = entity.investors.where(investor_name:, category: "Portfolio Company").first
    raise "Investor #{investor_name} not found" if investor.nil?

    investment_instrument = investor.investment_instruments.where(name: instrument_name).first
    if Rails.env.test?
      investment_instrument = investor.investment_instruments.create(name: instrument_name, entity_id: investor.entity_id, currency: entity.currency) if investment_instrument.nil?
    elsif investment_instrument.nil?
      raise "Investment Instrument #{instrument_name} not found"
    end

    valuation = investor.valuations.find_or_initialize_by(entity_id: investor.entity_id,
                                                          valuation_date:, per_share_value_cents:, investment_instrument:, valuation_cents:)

    if valuation.new_record?
      Rails.logger.debug user_data
      valuation.import_upload_id = import_upload.id
      setup_custom_fields(user_data, valuation, custom_field_headers)
      valuation.save!
    else
      raise "Valuation for #{investor_name} on #{valuation_date} already exists for entity #{investor.entity_id}"
    end

    true
  end
end
