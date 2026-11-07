module DashboardWidgetsHelper
  # Returns a hash of widgets for a given dashboard and entity.
  #
  # Criteria for returning a widget:
  # 1. The widget must be enabled.
  # 2. It must match the dashboard_name, name (default is "Default"), and entity_id.
  # 3. Show Menu does not filter here: the page shows every enabled widget and the menu is
  #    dashboard_menu_widgets of the same result, so the two cannot disagree (H1, H18, E2).
  # 4. If an owner is provided, it must match the owner.
  # 5. Filtering by tag_list (CSV string):
  #    - If tag_list is not provided, it falls back to owner.tag_list if the owner responds to it.
  #    - If the resulting tag_list is present:
  #      - Widgets with an empty tag_list are ALWAYS returned.
  #      - Widgets with a tag_list are returned ONLY if at least one of their tags matches a tag in the requested tag_list.
  #    - If the resulting tag_list is blank:
  #      - Widgets with an empty tag_list are returned.
  #      - Widgets with a tag_list are NOT returned.
  # 6. If no widget is enabled for the dashboard, all available widgets for the dashboard are returned (H17, E1).
  #    Widgets that are enabled but all hidden by tags give an empty result, not the defaults (E7).
  def dashboard_widgets(dashboard_name, entity_id, name: "Default", owner: nil, tag_list: nil, lp: false)
    return lp_layout_widgets(dashboard_name, entity_id, name:, owner:) if lp

    widgets = configured_dashboard_widgets(dashboard_name, entity_id, name:, owner:, tag_list:)
    lp_allocated_portfolio?(dashboard_name, owner) ? widgets.slice(*lp_allocated_portfolio_keys(widgets)) : widgets
  end

  # ── Widget settings in place — openspec/changes/archive/2026-11-07-dashboard-widget-inline-settings ──────────────────────────

  # A widget's key on the page: its container id and the suffix of its turbo frame (same as the menu anchors)
  def widget_frame_key(widget)
    "#{widget.widget_name.parameterize.underscore}_#{widget.position}"
  end

  # Query params that name the widget for the settings popup: a saved widget by id, a default one by
  # dashboard, layout and widget name (D2)
  def widget_settings_params(widget, dashboard_name, layout)
    return { widget_id: widget.id } if widget.persisted?

    { dashboard_name:, layout: layout.presence || "Default", widget_name: widget.widget_name }
  end

  # Whether this page shows the settings icons (H1, X1, X3): only on the user's own firm's dashboards, never in an
  # LP context, and only when the policy allows it. Worked out once per dashboard and layout, not per widget.
  def widget_settings_allowed?(dashboard_name, layout, entity_id:, lp: false)
    return false if lp || current_user.nil? || entity_id.to_i != current_user.entity_id

    # Memoised per request, false results included
    @widget_settings_allowed ||= {}
    key = [dashboard_name, layout]
    return @widget_settings_allowed[key] if @widget_settings_allowed.key?(key)

    @widget_settings_allowed[key] =
      policy(DashboardWidget.new(entity_id: current_user.entity_id, dashboard_name:, name: layout.presence || "Default"))
      .inline_settings?
  end

  # The icon shown beside a setting's label in the settings panel, by the kind of setting (and a few telling keys)
  def metadata_field_icon(kind, key)
    key = key.to_s
    return "ti-calendar" if key.include?("date")
    return "ti-heading" if key.include?("title") || key.include?("name")

    { boolean: "ti-toggle-left", choice: "ti-list-details", number: "ti-hash", list: "ti-list" }.fetch(kind, "ti-forms")
  end

  # The tooltip of a setting that has no hint of its own
  def metadata_field_default_tip(kind)
    case kind
    when :boolean then "ON or OFF. Default lets the widget decide."
    when :choice then "Pick one. Default lets the widget decide."
    when :number then "A number. Leave it empty to use the widget's default."
    when :list then "A comma-separated list. Leave it empty to use the widget's default."
    else "Leave it empty to use the widget's default."
    end
  end

  # The menu is the page's widgets narrowed by Show Menu. Default widgets reach here with show_menu true
  # (the column default), so a dashboard with nothing enabled lists its defaults in the menu too.
  def dashboard_menu_widgets(widgets)
    widgets.select { |_key, widget| widget.show_menu }
  end

  # The LP Company Dashboard's widgets: the chosen LP layout's enabled, LP-safe widgets, narrowed by the company's
  # own tags only (E86 — never the viewing LP's tags, E87) and never the default catalogue (E54).
  # Worked examples H11, E47, E54, E86, E87 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
  def lp_layout_widgets(dashboard_name, entity_id, name:, owner:)
    available = DashboardWidget::WIDGETS[dashboard_name].index_by(&:widget_name)
    # E97 — KPI widgets are skipped when the fund manager has no KPI module, even if a layout still holds them
    widgets = DashboardWidget.enabled.where(dashboard_name:, name:, entity_id:, widget_name: DashboardWidget.lp_safe_widget_names(Entity.find_by(id: entity_id)))
    company_tags = owner.respond_to?(:tag_list) ? owner.tag_list.to_s.presence : nil
    widgets.order(:position).filter_map do |widget|
      next unless available[widget.widget_name] && include_widget_by_tag?(widget, company_tags)

      widget.path = available[widget.widget_name].path
      ["#{widget.widget_name} #{widget.tags}", widget]
    end.to_h
  end

  # LP versions of the widgets whose internal data screens are for the fund team (KPI grids, valuations, stats):
  # they read Actual-only data limited to the LP's fund. The other LP-safe widgets render their usual partial.
  LP_WIDGET_PARTIALS = {
    "Kpis" => "lp_company_dashboards/widgets/kpis",
    "Kpis Performance Table" => "lp_company_dashboards/widgets/kpis",
    "Valuations" => "lp_company_dashboards/widgets/valuations",
    "Portfolio Stats" => "lp_company_dashboards/widgets/stats"
  }.freeze

  def lp_widget_partial(widget)
    LP_WIDGET_PARTIALS.fetch(widget.widget_name, widget.path)
  end

  # E42 — under an Allocated LP portfolio view an LP's fund Portfolio Dashboard keeps only widgets that list
  # the LP's own holdings; fund-wide charts (FMV %, IRR, fund stats…) would show the whole fund.
  # openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
  def lp_allocated_portfolio?(dashboard_name, owner)
    dashboard_name == DashboardWidget::PORTFOLIO_DASHBOARD && owner.is_a?(Fund) &&
      try(:current_user)&.curr_role_investor? && owner.lp_folio_portfolio?
  end

  def lp_allocated_portfolio_keys(widgets)
    widgets.select { |_key, widget| DashboardWidget::LP_ALLOCATED_PORTFOLIO_WIDGETS.include?(widget.widget_name) }.keys
  end

  def configured_dashboard_widgets(dashboard_name, entity_id, name: "Default", owner: nil, tag_list: nil)
    # These are the available widgets for the dashboard_name, defined in DashboardWidget::WIDGETS
    available_widgets = DashboardWidget::WIDGETS[dashboard_name].index_by(&:widget_name)

    # Step 1: Fetch custom widgets from the database that are enabled and match the dashboard criteria.
    widgets = DashboardWidget.enabled.where(dashboard_name:, name:, entity_id:)

    # Step 4: Build tag_list from owner and current_user so widget.tag_list can filter
    # by either owner tags (e.g. Fund category) OR user role tags (e.g. CFO, Admin).
    tag_list ||= owner.tag_list if owner.respond_to?(:tag_list)
    user_tags = try(:current_user)&.tag_list.to_s.presence
    tag_list  = [tag_list, user_tags].compact_blank.join(",").presence
    Rails.logger.debug { "Filtering widgets for dashboard '#{dashboard_name}' with tags: #{tag_list} for owner #{owner}" }

    if widgets.empty?
      # Step 5a: If no custom widgets are configured for this dashboard/entity/owner, return the default set
      # (the first four on landing pages — DashboardWidget.default_widgets_for owns that rule)
      DashboardWidget.default_widgets_for(dashboard_name).index_by(&:widget_name)
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

  # Pick-list for a setting whose hint names a +choices+ source on the Widget Configuration form. Returns
  # [[label, key], ...]; empty for an unknown source. H14 — the group-by list is the grid's own columns plus Fund Name.
  # H1 — the stats widgets' cards; E12 — the firm's currencies for the Default currency
  def metadata_choices(source, entity)
    case source
    when :stats_fields then return PortfolioCompanyStats::FIELDS.map { |name| [name, name] }
    when :entity_currencies then return (entity&.currency_list || []).map { |currency| [currency, currency] }
    end
    return [] unless source == :portfolio_investment_columns

    columns = entity&.form_types&.find_by(name: "PortfolioInvestment")&.ag_selected_columns.presence ||
              PortfolioInvestment.ag_grids_default_columns
    choices = columns.map { |column| [column[:label], column[:key]] }
    choices << ["Fund Name", "fund_name"] if choices.none? { |_label, key| key == "fund_name" }
    choices.uniq(&:last)
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
