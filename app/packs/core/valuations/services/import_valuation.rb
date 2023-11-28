class ImportValuation < ImportUtil
  include Interactor

  STANDARD_HEADERS = ["Category", "Sub Category", "Valuation Date", "Valuation", "Per Share Value", "Portfolio Company", "Pan"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def post_process(import_upload, _context); end

  def save_valuation(user_data, import_upload, custom_field_headers)
    # puts "processing #{user_data}"
    valuation_date = user_data['Valuation Date']
    valuation_cents = user_data['Valuation'].to_d * 100
    per_share_value_cents = user_data['Per Share Value'].to_d * 100
    investor_name = user_data['Portfolio Company']
    category = user_data['Category']
    sub_category = user_data['Sub Category']
    entity = import_upload.entity

    investor = entity.investors.find_or_initialize_by(investor_name:, category: "Portfolio Company")
    if investor.new_record?
      investor.pan = user_data['Pan'].to_s
      investor.save
    end

    valuation = investor.valuations.find_or_initialize_by(entity_id: investor.entity_id,
                                                          valuation_date:, per_share_value_cents:, category:, sub_category:, valuation_cents:)

    if valuation.new_record?
      Rails.logger.debug user_data
      setup_custom_fields(user_data, valuation, custom_field_headers)
      valuation.save!
    else
      Rails.logger.debug { "valuation for #{investor_name} on #{valuation_date} already exists for entity #{investor.entity_id}" }
    end

    true
  end

  def process_row(headers, custom_field_headers, row, import_upload, _context)
    # create hash from headers and cells

    user_data = [headers, row].transpose.to_h
    Rails.logger.debug { "#### user_data = #{user_data}" }
    begin
      if save_valuation(user_data, import_upload, custom_field_headers)
        import_upload.processed_row_count += 1
        row << "Success"
      else
        import_upload.failed_row_count += 1
        row << "Error"
      end
    rescue ActiveRecord::Deadlocked => e
      raise e
    rescue StandardError => e
      Rails.logger.debug e.message
      row << "Error #{e.message}"
      Rails.logger.debug user_data
      Rails.logger.debug row
      import_upload.failed_row_count += 1
    end
  end
end
