class AddSebiFields < SebiFieldsActions
  step :enable_sebi_fields
  step :add_sebi_custom_fields_to_instrument, Output(:failure) => End(:failure)
  step :add_sebi_custom_fields_to_kyc, Output(:failure) => End(:failure)
  step :save
  left :handle_errors, Output(:failure) => End(:failure)

  def enable_sebi_fields(_ctx, entity:, **)
    entity.permissions.set(:enable_sebi_fields)
  end

  def add_sebi_custom_fields_to_instrument(ctx, entity:, **)
    add_custom_fields_to_form(ctx, "InvestmentInstrument", entity)
  end

  def add_sebi_custom_fields_to_kyc(ctx, entity:, **)
    result = add_custom_fields_to_form(ctx, "IndividualKyc", entity)
    return false unless result

    add_custom_fields_to_form(ctx, "NonIndividualKyc", entity)
  end

  def add_custom_fields_to_form(ctx, class_name, entity)
    form_type = FormType.find_or_create_by(name: class_name, entity_id: entity.id)
    class_name.constantize::SEBI_REPORTING_FIELDS.each do |cust_field_key, type|
      add_custom_field(ctx, form_type, class_name, cust_field_key, type, entity)
    end
    entity.errors.blank?
  end

  def add_custom_field(ctx, form_type, class_name, cust_field_key, type, entity)
    cust_field_key = cust_field_key.to_s
    return if form_type.form_custom_fields.exists?(name: cust_field_key, field_type: type)

    label = generate_label(cust_field_key)
    params = generate_params(cust_field_key, label, type, class_name)

    begin
      form_type.form_custom_fields.create!(params)
    rescue StandardError => e
      handle_custom_field_error(ctx, cust_field_key, type, form_type, e, entity)
    end
  end

  def generate_label(cust_field_key)
    label = cust_field_key.humanize.titleize
    label = label.upcase if label.casecmp?("isin")
    label += " (if Type of Security chosen is Others)" if label.casecmp?("details of security")
    label
  end

  def generate_params(cust_field_key, label, type, class_name)
    params = {
      name: cust_field_key,
      label: label,
      field_type: type,
      internal: true
    }
    if type == "Select"
      metadata = if cust_field_key == "investor_sub_category" && class_name.ends_with?("Kyc")
                   class_name.constantize::SEBI_INVESTOR_SUB_CATEGORIES_MAPPING.values.flatten.join(',').to_s
                 else
                   ",#{class_name.constantize::SELECT_FIELDS_OPTIONS.stringify_keys[cust_field_key].join(',')}"
                 end
      if cust_field_key == "investor_category" && class_name.ends_with?("Kyc")
        # app/javascript/controllers/form_custom_fields_controller.js initialize and updateSubcategories method manipulate dropdowns
        js_events = "change->form-custom-fields#investor_category_changed"
        params[:js_events] = js_events
      end
      params[:meta_data] = metadata
      params[:step] = 1
    end
    params
  end

  def handle_custom_field_error(ctx, cust_field_key, type, form_type, error, entity)
    msg = "Error creating custom field for #{cust_field_key} with type #{type} for #{form_type.name} - #{error.message}"
    Rails.logger.error(msg)
    entity.errors.add(:base, msg)
    ctx[:errors] = msg
  end
end
