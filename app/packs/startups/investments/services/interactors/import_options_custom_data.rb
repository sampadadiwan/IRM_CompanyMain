class ImportOptionsCustomData < ImportUtil
  STANDARD_HEADERS = ["Email", "Option Pool"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def process_row(headers, custom_field_headers, row, import_upload, _context)
    # create hash from headers and cells

    user_data = [headers, row].transpose.to_h
    begin
      if save_holding(user_data, import_upload, custom_field_headers)
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

  def save_holding(user_data, import_upload, custom_field_headers)
    # Create the user if he does not exists
    user = User.find_by(email: user_data['Email'].strip)
    option_pool = nil
    option_pool = OptionPool.approved.where(entity_id: import_upload.entity_id, name: user_data["Option Pool"].strip).first if user_data["Option Pool"].present?

    options = import_upload.entity.holdings.options.where(user_id: user.id)
    options = options.where(option_pool_id: option_pool.id) if option_pool

    options.each do |option|
      setup_custom_fields(user_data, option, custom_field_headers)
      option.save
    end

    true
  end
end
