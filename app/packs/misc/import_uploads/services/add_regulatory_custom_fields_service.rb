# Service to add regulatory custom fields to a form type
class AddRegulatoryCustomFieldsService
  # Adds all regulatory custom fields to the given form type
  # Skips if the form type is not a regulatory model
  def add_custom_fields_to_form(form_type)
    # Skip if the form type is not one of the regulatory models
    return if FormCustomField::REGULATORY_FIELD_MODELS.exclude?(form_type.name)
    return if form_type.reg_env.blank?

    # Iterate through all reporting fields and add them as custom fields
    form_type.reg_env.split(',').each do |reg_env|
      reg_env = reg_env.strip.upcase
      reg_env_key = reg_env.downcase.to_sym
      form_type.name.constantize::REPORTING_FIELDS[reg_env_key]&.each do |regulatory_field_key, details|
        add_custom_field(form_type, regulatory_field_key, details, reg_env)
      end
    end

    true
  end

  # Adds a single custom field to the form type
  # Updates the field if it exists, otherwise creates a new one
  def add_custom_field(form_type, regulatory_field_key, details, reg_env)
    regulatory_field_key = regulatory_field_key.to_s

    params = generate_params(regulatory_field_key, details, reg_env)

    if form_type.form_custom_fields.exists?(name: regulatory_field_key)
      # Update existing field attributes
      form_type.form_custom_fields.find_by(name: regulatory_field_key).assign_attributes(params)
    else
      # Create new custom field
      form_type.form_custom_fields.new(params)
    end
  end

  # Generates parameters for creating/updating a custom field
  # Handles metadata and JS events for select fields
  def generate_params(cust_field_key, details, reg_env)
    label = details[:label].presence || cust_field_key.humanize.titleize

    params = {
      name: cust_field_key,
      label: label,
      field_type: details[:field_type],
      internal: true,
      read_only: true,
      reg_env: reg_env,
      step: 100 # end step
    }
    params[:meta_data] = details[:meta_data] if details[:meta_data].present?
    params[:js_events] = details[:js_events] if details[:js_events].present?

    params
  end
end
