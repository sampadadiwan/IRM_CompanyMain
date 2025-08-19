class ImportFormCustomFields < ImportUtil
  # No custom fields for FormCustomField
  step nil, delete: :create_custom_fields

  STANDARD_HEADERS = [
    "Label", "Name", "Field Type", "Required",
    "Has Attachment", "Position", "Help Text",
    "Read Only", "Show User IDs", "Step", "Condition On", "Condition Criteria",
    "Condition Params", "Condition State", "Internal", "Regulatory Environment"
  ].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(row_data, import_upload, _custom_field_headers, _ctx)
    Rails.logger.debug row_data

    # If ID is present, we are updating an existing FormCustomField
    if row_data["ID"].blank?
      form_custom_field = FormCustomField.new(import_upload_id: import_upload.id)
    else
      # If ID is present, we are updating an existing FormCustomField
      form_custom_field = FormCustomField.joins(form_type).where(id: row_data["ID"], form_types: { entity_id: import_upload.entity_id }).first
      if form_custom_field.nil
        # If we can't find the FormCustomField, we raise an error
        raise "FormCustomField with ID #{row_data['ID']} not found for entity #{import_upload.entity_id} and import_upload #{import_upload.id}"
      end
    end

    form_custom_field.assign_attributes(
      name: row_data["Name"],
      label: row_data["Label"],
      field_type: row_data["Field Type"],
      required: row_data["Required"].downcase == "true",
      has_attachment: row_data["Has Attachment"].downcase == "true",
      position: row_data["Position"],
      help_text: row_data["Help Text"],
      read_only: row_data["Read Only"].downcase == "true",
      show_user_ids: row_data["Show User IDs"],
      step: row_data["Step"],
      condition_on: row_data["Condition On"],
      condition_criteria: row_data["Condition Criteria"],
      condition_params: row_data["Condition Params"],
      condition_state: row_data["Condition State"],
      internal: row_data["Internal"].downcase == "true",
      reg_env: row_data["Regulatory Environment"]
    )

    form_custom_field.form_type_id = import_upload.owner_id
    form_custom_field.save!
  end
end
