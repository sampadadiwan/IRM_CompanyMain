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

  def column_set(current_user, col_set)
    col_set ||= current_user.show_all_cols? ? "all" : nil
    col_set
  end

  def custom_columns(current_user, col_set)
    col_set ||= current_user.show_all_cols? ? "all" : nil
    render partial: "/layouts/custom_columns", locals: { current_user:, col_set: }
  end
end
