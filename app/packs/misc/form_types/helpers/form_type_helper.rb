module FormTypeHelper
  # model: the model that has the form_type
  # form: the form object
  # step: the step of the form, usually CFs are added to the end of the form
  # required: whether the CF is required or not, This is an ovverride when we want no validations for certain use cases like KYC form, which needs validations only from investor side, and no validations from fund side. This will override the defined custom form fields required attribute.
  def custom_form_fields(model, form, step: "end", required: nil)
    render partial: "/form_types/custom_form_fields", locals: { model:, form:, step: FormCustomField.steps[step.to_sym], required: } if model.form_type.present?
  end

  def file_fields(name, model, form, required: false)
    render "/form_custom_fields/file", field: FormCustomField.new(name:, field_type: "file", required:, form_type_id: model.form_type&.id), model:, f: form
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
