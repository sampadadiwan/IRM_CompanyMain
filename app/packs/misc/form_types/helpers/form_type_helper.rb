module FormTypeHelper
  # model: the model that has the form_type
  # form: the form object
  # step: the step of the form; only multi-step/wizard forms should pass this to render one
  #   page's worth of fields at a time. Single-page forms should leave this nil so that all
  #   visible custom fields render regardless of which step they're tagged with, since there's
  #   no separate page for any other step to appear on.
  # required: whether the CF is required or not, This is an ovverride when we want no validations for certain use cases like KYC form, which needs validations only from investor side, and no validations from fund side. This will override the defined custom form fields required attribute.
  def custom_form_fields(model, form, step: nil, required: nil, custom_fields: [])
    return if model.form_type.blank?

    struct = CustomFieldsProxy.new(model.properties) # model.properties aliases json_fields; proxy avoids OpenStruct method churn in form rendering
    # Always resolve to the enum name string so where(step:) works consistently across Rails versions.
    # In Rails 7.1+ passing an integer to where() on an enum column is unreliable; strings are safe.
    step_name = if step.is_a?(Integer)
                  FormCustomField.steps.key(step) # e.g. 4 → "four", 8 → "eight"
                elsif step.present?
                  step.to_s # :one → "one", "end" → "end"
                end

    fields = custom_fields.presence || model.form_type.form_custom_fields.includes(:rich_text_info).visible.not_regulatory

    fields = fields.where(step: step_name) if step_name.present?

    render partial: "/form_types/custom_form_fields", locals: { model:, form:, required:, struct:, fields: }
  end

  # allowed_types: Uppy allowedFileTypes (extensions like ".xlsx" or MIME types); defaults to any file.
  def file_fields(name, model, form, required: false, meta_data: nil, data_controller: nil, allowed_types: nil)
    render "/form_custom_fields/file", field: FormCustomField.new(name:, label: name, field_type: "file", required:, form_type_id: model.form_type&.id, meta_data:), model:, f: form, data_controller: data_controller, allowed_types: allowed_types
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

  # Human-readable tab label for a given step enum name string (e.g. "four") and optional form_type.
  # Fixed infrastructure steps get fixed names; extra steps (four–nine) use form_type.label_for_step when available.
  def step_tab_label(step_name, form_type = nil)
    step_int = FormCustomField.steps[step_name.to_s]
    case step_name.to_s
    when "one"   then "Step 1"
    when "two"   then "Step 2"
    when "three" then "Step 3"
    when "end"   then "End"
    else
      form_type ? form_type.label_for_step(step_int) : "Step #{step_int}"
    end
  end

  def get_form_type(name, entity_id: nil, form_type_id: nil)
    entity_id ||= current_user.entity_id
    form_type = form_type_id.present? ? FormType.find(form_type_id) : FormType.where(entity_id:, name:).first
    custom_fields = form_type ? form_type.form_custom_fields.visible.to_a : []
    custom_field_names = custom_fields.map(&:name)
    custom_headers = custom_field_names.map(&:titleize)
    custom_calcs = form_type ? form_type.form_custom_fields.calculations : []
    custom_calc_headers = form_type ? form_type.form_custom_fields.calculations.collect(&:human_label) : []
    # hash of field_name => field_type, used by callers that need type-aware value formatting (e.g. DateField → Date object)
    custom_field_types = custom_fields.to_h { |f| [f.name, f.field_type] }

    [form_type, custom_field_names, custom_headers, custom_calcs, custom_calc_headers, custom_field_types]
  end

  # field_types: hash of field_name => field_type (from get_form_type's 6th return value).
  # When provided, values are cast per field type so Excel treats them as the right kind of
  # cell (date/number) and applies locale-sensitive formatting, matching how native DB columns
  # of the same type behave, instead of exporting every custom field as plain text.
  def get_custom_values(model, form_type, custom_field_names, field_types: {})
    if form_type && model&.properties
      model.properties.values_at(*custom_field_names).each_with_index.map do |v, i|
        custom_value_for_export(v, field_types[custom_field_names[i]])
      end
    else
      []
    end
  end

  def custom_value_for_export(v, field_type)
    return v.to_s if v.blank?

    case field_type
    when "DateField"
      begin
        Date.parse(v.to_s)
      rescue StandardError
        v.to_s
      end
    when "NumberField", "Money"
      begin
        Float(v.to_s)
      rescue ArgumentError, TypeError
        v.to_s
      end
    when "MultiSelect"
      v.is_a?(Array) ? v.join(", ") : v.to_s
    when "CheckBox"
      ["true", true, "1", 1].include?(v) ? "Yes" : "No"
    else
      v.to_s
    end
  end

  def excel_text_if_numeric(value)
    return value unless value.is_a?(String)

    # if value contains only digits, prefix with tab to force excel to treat as text
    value.match?(/\A\d+\z/) ? "\t#{value}" : value
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
