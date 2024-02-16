module ApplicationHelper
  def display_boolean(field)
    render(DisplayBooleanComponent.new(bool: field))
  end

  def upload_server
    Rails.configuration.upload_server
  end

  def last_folders_path(path_name, length)
    parts = path_name.split("/")
    parts.length > length ? parts[-length..].join("/") : path_name
  end

  def belongs_to_entity_id?(user, entity_id)
    user.entity_id == entity_id ||
      (user.entity_type == "Group Company" && user.entity.child_ids.include?(entity_id))
  end

  def download_xl_link(data_source)
    uri = URI.parse(data_source)
    query = Rack::Utils.parse_query(uri.query)
    uri.query = Rack::Utils.build_query(query)
    uri.to_s.gsub(".json", ".xlsx")
  end

  def uploaded_file_name(file)
    file.metadata['filename'] if file.metadata
  end

  def custom_grid_columns(entity, form_type_name)
    form_type = entity.form_types.where(name: form_type_name).first
    # Get the custom column names
    grid_column_names = form_type.form_custom_fields.where(field_type: "GridColumns", name: "grid_column_names").last
    # Get the custom column db field names
    grid_column_values = form_type.form_custom_fields.where(field_type: "GridColumns", name: "grid_column_values").last
    # Return the custom column names and values
    [grid_column_names&.meta_data&.split(","), grid_column_values&.meta_data&.split(",")]
  end

  def get_columns(model_class, params: {})
    # Default Columns for KYC
    column_names ||= params[:column_names].presence || model_class::STANDARD_COLUMN_NAMES
    field_list ||= params[:column_fields].presence || model_class::STANDARD_COLUMN_FIELDS

    # Custom Columns if applicable
    entity = @current_entity.presence || current_user.entity
    custom_cols = entity.customization_flags.send(:"#{model_class.name.underscore}_custom_cols?")
    column_names, field_list = custom_grid_columns(entity, model_class.name) if custom_cols

    # Add Fund if fund is not present
    if params[:no_fund].blank? && params[:fund_id].blank? && params[:capital_call_id].blank? && params[:capital_commitment_id].blank?
      column_names = ["Fund"] + column_names
      field_list = ["fund_name"] + field_list
    end

    # Remove Capital Call if capital call is present
    if params[:capital_call_id].present?
      column_names -= ["Capital Call"]
      field_list -= ["capital_call_name"]
    end

    # Remove Investor and Folio if capital commitment is present
    if params[:capital_commitment_id].present?
      column_names -= ["Investor", "Folio No"]
      field_list -= %w[investor_name folio_id]
    end

    if params[:investor_id].present?
      column_names -= ["Investor"]
      field_list -= %w[investor_name]
    end

    [column_names.join(","), field_list.join(",")]
  end

  def chart_theme_color
    if cookies[:theme] == "dark"
      { chart: { backgroundColor: "#2a3447" },
        xAxis: {
          labels: { style: {
            color: 'white'
          } }
        },
        yAxis: {
          labels: { style: {
            color: 'white'
          } }
        } }
    else
      {}
    end
  end

  def cache_key(key, include_theme: false)
    key = [key, current_user, current_user&.entity, current_user&.curr_role, params[:page]]
    key << cookies[:theme] if include_theme
    key
  end
end
