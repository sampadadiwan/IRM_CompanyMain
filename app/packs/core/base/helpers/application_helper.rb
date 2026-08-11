module ApplicationHelper
  include Pagy::Backend
  include Pagy::Frontend

  # Renders a locale-formatted display input with a calendar icon that opens the native
  # browser date picker. The actual submission uses a hidden ISO input so date parsing
  # is unaffected by locale on the server side.
  def date_field_tag(name, value = nil, options = {})
    date        = coerce_date_tag(value)
    css_class   = options.delete(:class) || "form-control"
    # Derive id the same way Rails does for tag helpers: replace [] with _ and strip trailing _
    field_id    = options.delete(:id) || name.to_s.delete("]").gsub(/[^a-zA-Z0-9_:.-]/, "_").gsub(/_+/, "_").gsub(/_\z/, "")
    i18n_format = I18n.t("date.formats.default")
    locale_val  = date ? l(date) : ""
    iso_val     = date ? date.iso8601 : ""

    # Extract interactive/constraint attributes — they belong on the visible and picker inputs.
    # required/disabled on a type="hidden" input are ignored by browsers; min/max have no
    # meaning there either. We apply them to the display input and the native picker instead.
    disabled    = options.delete(:disabled)
    required    = options.delete(:required)
    readonly    = options.delete(:readonly)
    min_val     = options.delete(:min)
    max_val     = options.delete(:max)
    # Deep-merge so the caller's data attributes survive alongside our Stimulus target marker
    caller_data = options.delete(:data) || {}
    hidden_data = caller_data.deep_merge({ "locale-date-target": "hidden" })

    content_tag(:div, class: "input-group",
      data: { controller: "locale-date", "locale-date-format-value": i18n_format }
    ) do
      # Display-only text input — has the id so Capybara/tests can find it; no name, never submitted
      display = tag.input(
        type:         "text",
        id:           field_id,
        value:        locale_val,
        class:        css_class,
        autocomplete: "off",
        disabled:     disabled,
        required:     required,
        readonly:     readonly,
        data:         {
          "locale-date-target": "display",
          action: "click->locale-date#openPicker input->locale-date#inputChanged"
        }
      )
      # Hidden ISO input — carries the actual value for form submission; id suppressed (lives on display)
      hidden = hidden_field_tag(name, iso_val,
        options.merge(id: nil, data: hidden_data)
      )
      icon_span = content_tag(:span, class: "input-group-text",
        style: "cursor:pointer;",
        data:  { action: "click->locale-date#openPicker" }
      ) do
        concat tag.i(class: "fas fa-calendar", style: "pointer-events:none;")
        # Zero-size invisible input — only purpose is to receive showPicker() and fire change events
        concat tag.input(
          type:     "date",
          value:    iso_val,
          min:      min_val,
          max:      max_val,
          disabled: disabled,
          style:    "position:absolute; width:0; height:0; opacity:0; overflow:hidden;",
          data:     { "locale-date-target": "picker", action: "change->locale-date#pickerChanged" }
        )
      end
      display + hidden + icon_span
    end
  end

  private

  def coerce_date_tag(value)
    return nil if value.blank?
    return value.to_date if value.is_a?(Date) || value.is_a?(Time)
    Date.local_parse(value.to_s)
  rescue StandardError
    nil
  end

  public

  attr_accessor :use_custom_colors

  def t_common(key)
    t("common.#{key}")
  end

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

  def owner_entity(model_records, current_user)
    return current_user.entity if %w[company_admin employee].include?(current_user.curr_role)

    model_records.first&.entity || current_user.entity
  end

  def chart_theme_color
    admin_settings = parse_json(cookies[:adminSettings]) || {}
    if admin_settings["Theme"] == "dark"
      { chart: { backgroundColor: "#2a3447" },
        xAxis: {
          lineColor: "#7c8fac",
          gridLineColor: "#7c8fac",
          labels: { style: { color: 'white' } }
        },
        yAxis: {
          gridLineWidth: 0.2,
          gridLineColor: "#7c8fac",
          labels: { style: { color: 'white' } }
        },
        labelColor: 'white' }
    else
      { labelColor: 'black' }
    end
  end

  # Generates Highcharts configuration for clickable chart slices.
  # This allows charts to act as interactive filters for data tables.
  #
  # @param param [String] The Ransack query parameter to apply (e.g., "q[category_eq]")
  # @param frame_id [String] The ID of the Turbo Frame to refresh (defaults to 'investors_frame')
  # @return [Hash] Highcharts plotOptions configuration
  def clickable_chart_options(param, frame_id: 'investors_frame')
    # Resolve the actual frame ID (handles report-specific frame naming)
    actual_frame_id = with_frame(frame_id)
    {
      plotOptions: {
        series: {
          cursor: 'pointer', # Change cursor to indicate interactivity
          clickable: true,   # Custom flag for the global JS listener
          clickParam: param, # The Ransack parameter to pass to JS
          clickFrameId: actual_frame_id # The target frame to refresh
        }
      }
    }
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
    if include_theme
      admin_settings = parse_json(cookies[:adminSettings]) || {}
      key << admin_settings["Theme"]
    end
    key
  end

  def bulk_action_button(action, msg, options = {})
    label = options[:label] || action.titleize
    button_to label, bulk_actions_documents_path(bulk_action: action, q: params.to_unsafe_h[:q], **options),
              class: "dropdown-item",
              data: { msg:, action: "click->confirm#popup", method: :post }
  end

  def ransack_query_params(name, predicate, value, idx: 0)
    RansackQueryBuilder.single(name, predicate, value, idx: idx)
  end

  def ransack_query_params_multiple(name_predicate_value_arr, sort_by: nil, sort_direction: "asc")
    RansackQueryBuilder.multiple(name_predicate_value_arr, sort_by: sort_by, sort_direction: sort_direction)
  end

  def deep_locate(params, key, value)
    result = params.to_unsafe_h.extend(Hashie::Extensions::DeepLocate).deep_locate ->(k, v, _object) { k == key && v.include?(value) }
    result.present?
  end

  def names_options_humanize(names)
    options = names.map do |field|
      [field.humanize.titleize, field]
    end
    options.sort_by! { |label, _value| label }
  end

  def sortable_header(q, attr, label, **)
    sort_link(q, attr, **) do
      active_sort = q.sorts.find { |s| s.name == attr.to_s }

      icon_up = ''.html_safe
      icon_down = ''.html_safe

      case active_sort&.dir
      when 'asc'
        icon_down = content_tag(:span, "▼", class: "arrow")
      when 'desc'
        icon_up = content_tag(:span, "▲", class: "arrow")
      else
        icon_up = content_tag(:span, "▲", class: "arrow")
        icon_down = content_tag(:span, "▼", class: "arrow")
      end

      safe_join([label, content_tag(:span, icon_up + icon_down, class: "sort-icons")], ' ')
    end
  end
  # rubocop:enable Naming/MethodParameterName

  # This method is used to display the ordinal suffix for a given day
  def ordinal(day)
    return "#{day}th" if (11..13).cover?(day % 100)

    case day % 10
    when 1 then "#{day}st"
    when 2 then "#{day}nd"
    when 3 then "#{day}rd"
    else "#{day}th"
    end
  end

  def date_with_ordinal(date, format: :default)
    format = format.present? ? format.to_s : "default"
    format = format&.to_sym
    if format == :ordinal
      "#{ordinal(date.day)} #{l(date, format: :month_year)}"
    else
      l(date, format: format)
    end
  end

  def use_custom_colors?
    if @use_custom_colors.nil?
      @use_custom_colors = (@current_entity && @current_entity.custom_css.present?) || params[:custom_css].present?
    else
      @use_custom_colors
    end
  end

  def pie_chart_colors_from_css
    @pie_chart_colors_from_css ||= (1..15).map { |i| "var(--pie-color-#{i})" }
    @pie_chart_colors_from_css
  end

  # True when a notes/tasks list is scoped to exactly one owner — a stakeholder's
  # or deal investor's own tab. Every row then repeats the same name, so the
  # "For" column is dead weight and gets dropped.
  #
  # Deliberately false for the two mixed-owner scopes that also pass owner params:
  #   * a contact's page (touch_point_scope=all) spans the LP's own records AND
  #     its deal investors' — there the column is the only thing distinguishing them
  #   * a deal's Tasks tab (deal_id) spans the Deal and every DealInvestor on it
  def single_owner_list?
    params[:owner_id].present? && params[:owner_type].present? &&
      params[:touch_point_scope] != "all" && params[:deal_id].blank?
  end

  def resolve_doc_color(document_name, custom_colors)
    name = document_name.to_s.downcase

    match = custom_colors.fetch("match", {})
                         .transform_keys { |k| k.to_s.downcase }

    return match[name] if match[name]

    custom_colors.fetch("contain", {}).each do |keyword, color|
      return color if name.include?(keyword.to_s.downcase)
    end

    nil
  end
end
