module FormTypeHelper
  # model: the model that has the form_type
  # form: the form object
  # step: the step of the form, usually CFs are added to the end of the form
  # required: whether the CF is required or not, This is an ovverride when we want no validations for certain use cases like KYC form, which needs validations only from investor side, and no validations from fund side. This will override the defined custom form fields required attribute.
  def custom_form_fields(model, form, step: "end", required: nil, custom_fields: [])
    return if model.form_type.blank?

    struct = OpenStruct.new(model.properties)
    step = step.present? ? FormCustomField.steps[step.to_sym] : nil

    fields = custom_fields.presence || model.form_type.form_custom_fields.visible.not_regulatory

    fields = fields.where(step: step) if step.present?

    render partial: "/form_types/custom_form_fields", locals: { model:, form:, required:, struct:, fields: }
  end

  def file_fields(name, model, form, required: false, meta_data: nil)
    render "/form_custom_fields/file", field: FormCustomField.new(name:, label: name, field_type: "file", required:, form_type_id: model.form_type&.id, meta_data:), model:, f: form
  end

  def display_custom_fields(model, collapsed: false, custom_fields: [], timestamps_and_snapshot: true)
    form_custom_fields = if custom_fields.present?
                           # If custom_fields are passed, we use them directly
                           custom_fields
                         else
                           # Otherwise, we fetch the custom fields from the model's form_type
                           model.form_type.present? ? model.form_custom_fields.not_regulatory : []
                         end

    render partial: "/form_types/display_custom_fields", locals: { model:, collapsed:, form_custom_fields: form_custom_fields, timestamps_and_snapshot: }
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
    if form_type && model&.properties
      model.properties.values_at(*custom_field_names).map(&:to_s)
    else
      []
    end
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
