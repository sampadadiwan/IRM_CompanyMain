module FormTypeHelper
  # model: the model that has the form_type
  # form: the form object
  # step: the step of the form, usually CFs are added to the end of the form
  # required: whether the CF is required or not, This is an ovverride when we want no validations for certain use cases like KYC form, which needs validations only from investor side, and no validations from fund side. This will override the defined custom form fields required attribute.
  def custom_form_fields(model, form, step: "end", required: nil)
    render partial: "/form_types/custom_form_fields", locals: { model:, form:, step: FormCustomField.steps[step.to_sym], required: } if model.form_type.present?
  end

  def file_fields(name, model, form, required: false, meta_data: nil)
    render "/form_custom_fields/file", field: FormCustomField.new(name:, label: name, field_type: "file", required:, form_type_id: model.form_type&.id, meta_data:), model:, f: form
  end

  def display_custom_fields(model, collapsed: false)
    render partial: "/form_types/display_custom_fields", locals: { model:, collapsed: }
  end

  def get_form_type(name, entity_id: nil, form_type_id: nil)
    entity_id ||= current_user.entity_id
    form_type = form_type_id.present? ? FormType.find(form_type_id) : FormType.where(entity_id:, name:).first
    custom_field_names = form_type ? form_type.form_custom_fields.visible.collect(&:name) : []
    custom_headers = custom_field_names.map(&:titleize)
    custom_calcs = form_type ? form_type.form_custom_fields.calculations : []
    custom_calc_headers = form_type ? form_type.form_custom_fields.calculations.collect(&:human_label) : []

    [form_type, custom_field_names, custom_headers, custom_calcs, custom_calc_headers]
  end

  def get_custom_values(model, form_type, custom_field_names)
    form_type && model&.properties ? model.properties.values_at(*custom_field_names) : []
  end

  def get_custom_calc_values(model, form_type, custom_calcs)
    calc_values = []
    custom_calcs.each do |custom_calc|
      val = form_type && model&.properties ? model.perform_custom_calculation(custom_calc) : nil
      calc_values << val
    end
    calc_values
  end
end
