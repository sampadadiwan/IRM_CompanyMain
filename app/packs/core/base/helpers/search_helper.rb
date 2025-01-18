module SearchHelper
  ALLOWED_KEYS = %w[controller action utf8 commit per_page page search].freeze
  def add_hidden_fields_from_source(data_source)
    query_string = URI.parse(data_source).query
    params_hash = Rack::Utils.parse_nested_query(query_string)

    render partial: "layouts/form_hidden_field", locals: { params_hash:, allowed_keys: ALLOWED_KEYS }
  end
end
