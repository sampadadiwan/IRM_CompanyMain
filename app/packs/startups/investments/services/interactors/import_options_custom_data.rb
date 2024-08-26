class ImportOptionsCustomData < ImportUtil
  STANDARD_HEADERS = ["Email", "Option Pool"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
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
