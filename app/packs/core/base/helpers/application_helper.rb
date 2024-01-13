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
    [grid_column_names&.meta_data, grid_column_values&.meta_data]
  end
end
