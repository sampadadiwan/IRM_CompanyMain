module ApplicationHelper
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
    if cookies[:theme] == "dark"
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

  def ransack_query_params(name, predicate, value, idx: 0)
    { "c" => { idx.to_s => { "a" => { idx.to_s => { "name" => name } }, "p" => predicate, "v" => { idx.to_s => { "value" => value } } } } }
  end

  def ransack_query_params_multiple(name_predicate_value_arr, sort_by: nil, sort_direction: "asc")
    params = { "c" => {} }

    name_predicate_value_arr.each do |npv|
      name, predicate, value = npv
      unique_id = SecureRandom.hex(10)

      params["c"][unique_id] = {
        "a" => { "0" => { "name" => name } },
        "p" => predicate,
        "v" => { "0" => { "value" => value } }
      }
    end

    # Add sorting if specified
    params["s"] = "#{sort_by} #{sort_direction}" if sort_by.present?

    params
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
end
