class ImportDashboardWidget < ImportUtil
  # No custom fields for DashboardWidget
  step nil, delete: :create_custom_fields

  STANDARD_HEADERS = ["Dashboard Name", "Widget Name", "Position", "Tags", "Metadata", "Size", "Enabled", "Display Name", "Display Tag", "Name", "Show Menu"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def post_process(ctx, import_upload:, **)
    super
    true
  end

  def save_row(user_data, import_upload, _custom_field_headers, _ctx)
    id = user_data["Id"]
    dashboard_name = user_data["Dashboard Name"]
    widget_name = user_data["Widget Name"]
    position = user_data["Position"]
    tags = user_data["Tags"]
    metadata = user_data["Metadata"].strip.delete("\t") if user_data["Metadata"].present?

    size = user_data["Size"]
    # flag? treats a blank cell as false - calling downcase on it directly raised
    # a bare NoMethodError that named neither the row nor the column
    enabled = flag?(user_data["Enabled"])
    display_name = flag?(user_data["Display Name"])
    display_tag = flag?(user_data["Display Tag"])
    name = user_data["Name"]
    show_menu = flag?(user_data["Show Menu"])

    # The Id column carries the source system's ids, which will not exist in the
    # target entity - an unmatched id creates a new widget here by design
    widget = DashboardWidget.where(id:, entity_id: import_upload.entity_id).first

    if widget.present?
      Rails.logger.debug { "DashboardWidget #{id} already exists for entity #{import_upload.entity_id}, updating" }
      widget.assign_attributes(
        dashboard_name:, widget_name:, position:, tags:, metadata:, size:, enabled:, display_name:,
        display_tag:, name:, show_menu:, import_upload_id: import_upload.id, entity_id: import_upload.entity_id
      )
    else
      widget = DashboardWidget.new(
        dashboard_name:, widget_name:, position:, tags:, metadata:, size:, enabled:, display_name:,
        display_tag:, name:, show_menu:, import_upload_id: import_upload.id, entity_id: import_upload.entity_id
      )
    end

    Rails.logger.debug { "Saving DashboardWidget with name '#{widget.name}'" }
    widget.save!
  end
end
