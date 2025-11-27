class RansackQueryBuilder
  def self.multiple(name_predicate_value_arr, sort_by: nil, sort_direction: "asc")
    params = { "c" => {} }

    name_predicate_value_arr.each do |npv|
      name, predicate, value = npv
      unique_id = SecureRandom.hex(10)

      params["c"][unique_id] = {
        "a" => { "0" => { "name" => name } },
        "p" => predicate,
        "v" => build_values_hash(value)
      }
    end

    # Add sorting if specified
    params["s"] = "#{sort_by} #{sort_direction}" if sort_by.present?

    params
  end

  def self.build_values_hash(value)
    if value.is_a?(Array)
      if value.empty?
        { "0" => { "value" => nil } }
      else
        value.each_with_index.with_object({}) do |(val, idx), h|
          h[idx.to_s] = { "value" => val }
        end
      end
    else
      { "0" => { "value" => value } }
    end
  end

  def self.single(name, predicate, value, idx: 0)
    { "c" => { idx.to_s => { "a" => { idx.to_s => { "name" => name } }, "p" => predicate, "v" => { idx.to_s => { "value" => value } } } } }
  end
end
