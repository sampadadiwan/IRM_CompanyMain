module GridColsHelper
  def custom_grid_columns(entity, form_type_name)
    form_type = entity.form_types.where(name: form_type_name).first
    # Get the custom column names
    grid_column_names = form_type.form_custom_fields.where(field_type: "GridColumns", name: "grid_column_names").last
    # Get the custom column db field names
    grid_column_values = form_type.form_custom_fields.where(field_type: "GridColumns", name: "grid_column_values").last
    # Return the custom column names and values
    [grid_column_names&.meta_data&.split(","), grid_column_values&.meta_data&.split(",")]
  end

  def get_columns_as_hash(model_class, _params: {})
    column_names, field_list = get_columns(model_class, params: {})
    column_names.split(",").zip(field_list.split(",")).to_h
  end

  def get_columns(model_class, params: {})
    # Default Columns for KYC
    column_names ||= params[:column_names].presence
    field_list ||= params[:column_fields].presence

    if current_user.curr_role == "investor"
      column_names ||= model_class::INVESTOR_STANDARD_COLUMNS.keys
      field_list ||= model_class::INVESTOR_STANDARD_COLUMNS.values
    else
      column_names ||= model_class::STANDARD_COLUMNS.keys
      field_list ||= model_class::STANDARD_COLUMNS.values
    end

    # Custom Columns if applicable
    entity = @current_entity.presence || current_user.entity
    # Ex : investor_custom_cols or individual_kyc_custom_cols
    customization_flag_name = :"#{model_class.name.underscore}_custom_cols"
    custom_cols = entity.customization_flags.set?(customization_flag_name)
    column_names, field_list = custom_grid_columns(entity, model_class.name) if custom_cols

    add_remove_custom_columns(params, column_names, field_list)

    [column_names.join(","), field_list.join(",")]
  end

  def add_remove_custom_columns(params, _column_names, field_list)
    field_list = ["fund_name"] + field_list if params[:no_fund].blank? && params[:fund_id].blank? && params[:capital_call_id].blank? && params[:capital_commitment_id].blank?

    # Remove Capital Call if capital call is present
    field_list -= ["capital_call_name"] if params[:capital_call_id].present?

    # Remove Investor and Folio if capital commitment is present
    field_list -= %w[investor_name folio_id] if params[:capital_commitment_id].present?

    field_list - %w[investor_name] if params[:investor_id].present?
  end
end
