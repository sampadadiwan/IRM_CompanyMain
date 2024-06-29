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
    custom_cols = if entity.customization_flags.respond_to?(:"#{model_class.name.underscore}_custom_cols?")
                    entity.customization_flags.send(:"#{model_class.name.underscore}_custom_cols?")
                  else
                    false
                  end
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

  def chart_theme_color
    if cookies[:theme] == "dark"
      { chart: { backgroundColor: "#2a3447" },
        xAxis: {
          lineColor: "#7c8fac",
          # gridLineWidth: 0.5,
          gridLineColor: "#7c8fac",
          labels: { style: {
            color: 'white'
          } }
        },
        yAxis: {
          # lineColor: "#7c8fac",
          gridLineWidth: 0.2,
          gridLineColor: "#7c8fac",
          labels: { style: {
            color: 'white'
          } }
        } }
    else
      {}
    end
  end

  def parse_json(obj)
    JSON.parse(obj)
  rescue JSON::ParserError, TypeError
    nil
  end

  def json2table(json, table_options: nil)
    table_options ||= { table_class: "table table-bordered dataTable no_hover_table" }.freeze
    Json2table.get_html_table(json, table_options)
  end

  def cache_key(key, include_theme: false)
    key = [key, current_user, current_user&.entity, current_user&.curr_role, params[:page], params[:units]]
    key << cookies[:theme] if include_theme
    key
  end

  def bulk_action_button(action, msg, options = {})
    label = options[:label] || action.titleize
    button_to label, bulk_actions_documents_path(bulk_action: action, q: params.to_unsafe_h[:q], **options),
              class: "dropdown-item",
              data: { msg:, action: "click->confirm#popup", method: :post }
  end

  def ransack_query_params(name, predicate, value)
    { "c" => { "0" => { "a" => { "0" => { "name" => name } }, "p" => predicate, "v" => { "0" => { "value" => value } } } } }
  end
end
