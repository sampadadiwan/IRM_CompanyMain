# Shared rules for the dashboard insight widgets (KPI Movers, Valuation Freshness, Remittance Ageing, Needs
# Attention, ...). Worked examples E1, E2, X2, X9 — openspec/changes/dashboard-insight-widgets/business-rules.md#1
module InsightWidgetsHelper
  # The 17 insight widgets show internal fund-manager data, so none of them renders for a user acting as an
  # investor, whatever dashboard URL that user requests (X2, X9). They are also left out of
  # DashboardWidget::LP_SAFE_WIDGET_NAMES, so they cannot be placed in an LP layout (X1).
  def insight_widget_visible?
    # No signed-in user means no view at all; an investor-role user never sees these widgets
    current_user.present? && !current_user.curr_role_investor?
  end

  # A whole-number setting, or the default when the setting is missing, zero, negative or not a whole number
  # (E1 — {top_n: 0} gives the default; E2 — {current_days: 'abc'} gives the default).
  def insight_int_arg(args, key, default)
    # Integer(..., exception: false) returns nil for "abc", "12.5" and blank instead of raising
    value = Integer(args[key].to_s.strip, 10, exception: false)
    value&.positive? ? value : default
  end

  # A text setting, or the default when it is blank
  def insight_str_arg(args, key, default)
    args[key].to_s.strip.presence || default
  end

  # A choice setting: the value when it is one of the allowed choices (case-insensitive), else the default
  def insight_choice_arg(args, key, choices, default)
    value = args[key].to_s.strip.downcase
    choices.find { |choice| choice.downcase == value } || default
  end

  # The one-sentence empty state every insight widget shows when it has nothing to list
  def insight_empty_state(message)
    content_tag(:p, message, class: "text-muted mb-0 py-3 text-center", data: { insight_empty_state: true })
  end

  # The one muted line under a widget's title that says what it lists and how to read it, so the widget
  # explains itself without opening the ⓘ
  def insight_help_line(text)
    content_tag(:div, text, class: "text-muted small mb-2", data: { insight_help: true })
  end

  # A table heading, with an ⓘ tooltip when the column's meaning or source is not obvious (shown through the
  # layout's tooltip controller, data-bs-toggle="tooltip")
  def insight_th(label, tooltip = nil, right: false)
    content_tag(:th, class: ("text-end" if right)) do
      # The label, then the ⓘ only when there is something to explain
      icon = tooltip && content_tag(:i, nil, class: "ti ti-info-circle ms-1", title: tooltip, data: { bs_toggle: "tooltip" })
      safe_join([label, icon].compact)
    end
  end

  # Money in the given currency, formatted the way the app formats money everywhere else
  def insight_money(cents, currency)
    money_to_currency(Money.new(cents.to_i, currency))
  end
end
