class ImportFormCustomField < ImportUtil
  # Remove the creation of custom fields - FormCustomField does not have custom fields
  step nil, delete: :create_custom_fields

  STANDARD_HEADERS = [
    "Label", "Name", "Field Type", "Required",
    "Has Attachment", "Position", "Help Text", "Metadata", "Info",
    "Read Only", "Show User IDs", "Step", "Condition On", "Condition Criteria",
    "Condition Params", "Condition State", "Internal", "Regulatory Environment"
  ].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(row_data, import_upload, _custom_field_headers, _ctx)
    Rails.logger.debug row_data

    # If ID is present, we are updating an existing FormCustomField
    if row_data["Id"].blank?
      form_custom_field = FormCustomField.new(import_upload_id: import_upload.id)
    else
      # If ID is present, we are updating an existing FormCustomField
      form_custom_field = FormCustomField.joins(:form_type).where(id: row_data["Id"], form_types: { entity_id: import_upload.entity_id }).first
      if form_custom_field.nil?
        # If we can't find the FormCustomField, we raise an error
        raise "FormCustomField with ID #{row_data['Id']} not found for entity #{import_upload.entity_id} and import_upload #{import_upload.id}"
      end
    end

    # N1 (OWASP 2026-11): Calculation fields hold Ruby, so only CapHive support may add or change one, here as
    # in the form editor (FormType.calculation_change_allowed?, C2) and FormCustomFieldPolicy
    guard_calculation_change!(form_custom_field, row_data, import_upload)

    step_value = row_data["Step"].to_s.strip

    step =
      if FormCustomField.steps.key?(step_value)
        step_value
      else
        "end"
      end

    form_custom_field.assign_attributes(
      name: row_data["Name"]&.strip,
      label: row_data["Label"]&.strip,
      field_type: row_data["Field Type"],
      required: row_data["Required"]&.downcase&.strip == "true",
      has_attachment: row_data["Has Attachment"]&.downcase&.strip == "true",
      position: row_data["Position"],
      help_text: row_data["Help Text"],
      read_only: row_data["Read Only"]&.downcase&.strip == "true",
      show_user_ids: row_data["Show User IDs"],
      step: step,
      condition_on: row_data["Condition On"],
      condition_criteria: row_data["Condition Criteria"],
      condition_params: row_data["Condition Params"],
      condition_state: row_data["Condition State"],
      internal: row_data["Internal"]&.downcase&.strip == "true",
      reg_env: row_data["Regulatory Environment"],
      meta_data: row_data["Metadata"],
      info: row_data["Info"],
      import_upload_id: import_upload.id
    )

    form_custom_field.form_type_id = import_upload.owner_id
    form_custom_field.save!
  end

  private

  # N1 — refuses the row when a non-support upload would create a Calculation field, turn a field into one, or
  # change a stored one (its type or its Ruby). The import records the reason against the row, as for any
  # other row error.
  # Allowed, so nothing that works today breaks:
  #   - uploads by support, including support signed in as the client (ImportUpload#uploaded_by_support?)
  #   - a stored Calculation field repeated unchanged: re-importing an exported sheet that lists it
  #   - development and test, as the form editor allows (Rails.env.local?)
  # @param field [FormCustomField] the row's field: new, or the stored one named by "Id"
  def guard_calculation_change!(field, row_data, import_upload)
    return if import_upload.uploaded_by_support? || Rails.env.local?

    submitted_type = row_data["Field Type"].to_s.strip
    stored_calculation = field.persisted? && field.field_type == "Calculation"
    # Rows that neither are nor become a Calculation field: nothing to check
    return unless submitted_type == "Calculation" || stored_calculation

    # The same Calculation field with the same Ruby: unchanged, so allowed
    unchanged = stored_calculation && submitted_type == "Calculation" &&
                row_data["Metadata"].to_s.strip == field.meta_data.to_s.strip
    return if unchanged

    raise "Calculation fields can only be added or changed by CapHive support (#{row_data['Name'].to_s.strip})"
  end
end
