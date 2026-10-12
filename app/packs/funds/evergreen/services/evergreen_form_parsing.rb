# Turns evergreen settings form inputs into stored values.
module EvergreenFormParsing
  module_function

  # "3:0-12, 2:12-24" (pct:from-to months) → {"schedule" => [...]}; else a flat {"pct" => x}
  def early_fee(pct, schedule_text, allow_nil: false)
    if schedule_text.present?
      bands = schedule_text.split(",").filter_map do |band|
        m = band.strip.match(/\A([\d.]+)\s*:\s*(\d+)\s*-\s*(\d+)\z/)
        { "pct" => m[1].to_d.to_s, "from" => m[2].to_i, "to" => m[3].to_i } if m
      end
      return { "schedule" => bands } if bands.any?
    end
    return nil if allow_nil && pct.blank?

    { "pct" => pct.to_d.to_s }
  end

  class BadDates < StandardError; end

  # Comma- or newline-separated ISO dates (YYYY-MM-DD) → ISO strings (nil when blank). Strict, so
  # "03/04/2027" isn't read day-first for one user and month-first for another, and one bad entry
  # is reported instead of silently emptying the whole list (review finding M4).
  def dates(text)
    return nil if text.blank?

    tokens = text.split(/[\n,]/).map(&:strip).compact_blank
    bad = tokens.reject do |d|
      d.match?(/\A\d{4}-\d{2}-\d{2}\z/) && begin
        Date.iso8601(d)
      rescue StandardError
        nil
      end
    end
    raise BadDates, "These dates are not valid YYYY-MM-DD dates: #{bad.join(', ')}" if bad.any?

    tokens.map { |d| Date.iso8601(d).iso8601 }
  end
end
