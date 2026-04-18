module DashboardWidgetsHelper
  # Returns a hash of widgets for a given dashboard and entity.
  #
  # Criteria for returning a widget:
  # 1. The widget must be enabled.
  # 2. It must match the dashboard_name, name (default is "Default"), and entity_id.
  # 3. If show_menu is provided, it must match.
  # 4. If an owner is provided, it must match the owner.
  # 5. Filtering by tag_list (CSV string):
  #    - If tag_list is not provided, it falls back to owner.tag_list if the owner responds to it.
  #    - If the resulting tag_list is present:
  #      - Widgets with an empty tag_list are ALWAYS returned.
  #      - Widgets with a tag_list are returned ONLY if at least one of their tags matches a tag in the requested tag_list.
  #    - If the resulting tag_list is blank:
  #      - Widgets with an empty tag_list are returned.
  #      - Widgets with a tag_list are NOT returned.
  # 6. If no custom widgets are found after filtering, all available widgets for the dashboard are returned.
  def dashboard_widgets(dashboard_name, entity_id, name: "Default", owner: nil, show_menu: nil, tag_list: nil)
    # These are the available widgets for the dashboard_name, defined in DashboardWidget::WIDGETS
    available_widgets = DashboardWidget::WIDGETS[dashboard_name].index_by(&:widget_name)

    # Step 1: Fetch custom widgets from the database that are enabled and match the dashboard criteria.
    widgets = DashboardWidget.enabled.where(dashboard_name:, name:, entity_id:)

    # Step 2: Apply optional filters from the query or parameters.
    widgets = widgets.where(show_menu:) if show_menu.present?

    # Step 4: Handle tag_list filtering. Fall back to owner's tag_list if none is provided.
    tag_list ||= owner.tag_list if owner.respond_to?(:tag_list)
    Rails.logger.debug { "Filtering widgets for dashboard '#{dashboard_name}' with tags: #{tag_list} for owner #{owner}" }

    if widgets.empty?
      # Step 5a: If no custom widgets are configured for this dashboard/entity/owner, return the default set.
      # For Landing Page, we only show a subset by default to avoid context-specific widget crashes
      if [DashboardWidget::FM_LANDING_PAGE, DashboardWidget::LP_LANDING_PAGE, DashboardWidget::OPS_LANDING_PAGE].include?(dashboard_name)
        DashboardWidget::WIDGETS[dashboard_name].take(3).index_by(&:widget_name)
      else
        DashboardWidget::WIDGETS[dashboard_name].index_by(&:widget_name)
      end
    else
      # Step 5b: If custom widgets exist, filter and transform them into a hash.
      dashboard_widgets = []
      widgets.order(:position).each do |widget|
        # Skip if the widget's name isn't recognized in the available_widgets map for this dashboard.
        next unless available_widgets[widget.widget_name]
        # Skip if the widget doesn't match the tag criteria (handled in private method).
        next unless include_widget_by_tag?(widget, tag_list)

        # Assign the partial path from the static available_widgets definition to the active record instance.
        widget.path = available_widgets[widget.widget_name].path
        # Format the result as [display_name, widget_object] for the final hash construction.
        dashboard_widgets << ["#{widget.widget_name} #{widget.tags}", widget]
      end

      # Step 6: Convert the array of pairs to a hash and ensure the final sorting matches widget.position.
      dashboard_widgets.to_h.sort_by { |_k, v| v.position || 0 }.to_h
    end
  end

  def report_url(dashboard_name, report)
    case dashboard_name
    when "Portfolio Company Dashboard"
      dynamic_report_path(report, portfolio_company_name: @investor.investor_name, investor_name: @investor.investor_name)
    else
      report_path(report)
    end
  end

  # Safely traverses a dot-separated field path on +object+ using only public
  # methods whose names consist of word characters and question/bang suffixes
  # (e.g. "city", "custom_fields.sector", "active?").  Any segment that does
  # not match the allowed pattern causes the traversal to stop and return nil,
  # preventing arbitrary method invocation (including private methods).
  #
  # @param object [Object] the root object to traverse (typically an Investor)
  # @param key_path [String] dot-separated attribute path, e.g. "custom_fields.sector"
  # @return [Object, nil] the resolved value, or nil if any segment is unsafe/missing
  SAFE_METHOD_SEGMENT = /\A[a-zA-Z_]\w*[?!]?\z/

  def safe_field_value(object, key_path)
    key_path.split(".").inject(object) do |obj, segment|
      method_name = segment.strip
      break nil unless method_name.match?(SAFE_METHOD_SEGMENT)

      obj&.public_send(method_name)
    end
  end

  private

  def include_widget_by_tag?(widget, tag_list)
    # If tag_list is provided
    if tag_list.present?
      requested_tags = tag_list.split(",").map(&:strip).compact_blank.map(&:downcase)
      widget_tags = widget.tag_list.to_s.split(",").map(&:strip).compact_blank.map(&:downcase)
      # Always include widgets with an empty tag_list.
      # Otherwise, return true if at least one of their tags matches a tag in the requested tag_list.
      widget_tags.blank? || requested_tags.intersect?(widget_tags)
    else
      # If tag_list is blank but the widget has a tag_list, then it should not be returned.
      widget.tag_list.blank?
    end
  end
end
