class RansackQueryBuilder
  def self.multiple(name_predicate_value_arr, sort_by: nil, sort_direction: "asc")
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

  def self.single(name, predicate, value, idx: 0)
    { "c" => { idx.to_s => { "a" => { idx.to_s => { "name" => name } }, "p" => predicate, "v" => { idx.to_s => { "value" => value } } } } }
  end
end
