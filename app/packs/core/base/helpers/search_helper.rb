module SearchHelper
  ALLOWED_KEYS = %w[controller action utf8 commit per_page page search].freeze

  def add_hidden_fields_from_source(data_source)
    query_string = URI.parse(data_source).query
    params_hash = Rack::Utils.parse_nested_query(query_string)
    flattened_params = flatten_params(params_hash).to_h

    render partial: "layouts/form_hidden_field", locals: {
      params_hash: flattened_params,
      allowed_keys: ALLOWED_KEYS
    }
  end

  def flatten_params(params, prefix = nil)
    result = []

    params.each do |key, value|
      full_key = prefix ? "#{prefix}[#{key}]" : key.to_s

      case value
      when Hash
        result.concat(flatten_params(value, full_key))
      when Array
        value.each_with_index do |v, i|
          if v.is_a?(Hash) || v.is_a?(Array)
            result.concat(flatten_params(v, "#{full_key}[#{i}]"))
          else
            result << ["#{full_key}[#{i}]", v]
          end
        end
      else
        result << [full_key, value]
      end
    end

    result
  end
end
