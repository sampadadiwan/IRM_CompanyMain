module FormTypeHelper
  def custom_form_fields(model, form, step: "end")
    render partial: "/form_types/custom_form_fields", locals: { model:, form:, step: FormCustomField.steps[step.to_sym] } if model.form_type.present?
  end

  def display_custom_fields(model, collapsed: false)
    render partial: "/form_types/display_custom_fields", locals: { model:, collapsed: }
  end

  def get_form_type(name)
    form_type = FormType.where(entity_id: current_user.entity_id, name:).first
    custom_field_names = form_type ? form_type.form_custom_fields.collect(&:name) : []
    custom_headers = custom_field_names.map(&:titleize)

    [form_type, custom_field_names, custom_headers]
  end

  def get_custom_values(model, form_type, custom_field_names)
    form_type && model&.properties ? model.properties.values_at(*custom_field_names) : []
  end
end
