# Display formatting for compliance figures — the same strings appear on screens, in the working,
# the digest and exports, so a result never contradicts what the user reads (R14).
module ComplianceFormat
  CRORE = 10_000_000

  module_function

  # ₹72.00 cr for crore-sized INR amounts; Indian grouping below a crore (₹10,00,000); USD 144,578
  def amount(value, currency = "INR")
    return "—" if value.nil?

    v = value.to_d
    if currency == "INR"
      return "₹#{format('%.2f', (v / CRORE).round(2))} cr" if v.abs >= CRORE

      "₹#{indian_grouping(v.round(0).to_i)}"
    else
      "#{currency} #{ActiveSupport::NumberHelper.number_to_delimited(v.round(0).to_i)}"
    end
  end

  # 0.266666 → "26.67%" (rounded to 2 decimals as displayed)
  def pct(ratio)
    return "—" if ratio.nil?

    "#{format('%.2f', pct_value(ratio))}%"
  end

  def pct_value(ratio)
    (ratio.to_d * 100).round(2)
  end

  def count(value)
    return "—" if value.nil?

    ActiveSupport::NumberHelper.number_to_delimited(value.to_d.round(0).to_i)
  end

  def by_unit(value, unit, currency = "INR")
    case unit
    when "pct" then pct(value)
    when "count" then count(value)
    else amount(value, currency)
    end
  end

  # Limit values in pct are entered as percentages (25), not ratios
  def limit(value, unit, currency = "INR")
    unit == "pct" ? "#{format('%.2f', value.to_d)}%".sub(".00%", "%") : by_unit(value, unit, currency)
  end

  def indian_grouping(int)
    sign = int.negative? ? "-" : ""
    s = int.abs.to_s
    return sign + s if s.length <= 3

    last3 = s[-3..]
    rest = s[0...-3].reverse.scan(/\d{1,2}/).join(",").reverse
    "#{sign}#{rest},#{last3}"
  end
end
