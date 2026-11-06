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

  # E197 / R162: remedy and headroom amounts always read in crores, like the steps above them —
  # "₹0.15 cr", never "₹15,00,000". Amounts under ₹1 lakh keep their digits ("₹45,000").
  def amount_cr(value, currency = "INR")
    return amount(value, currency) unless currency == "INR" && value && value.to_d.abs >= 100_000

    "₹#{format('%.2f', (value.to_d / CRORE).round(2))} cr"
  end

  # "22 investments made before this check started are not checked" (E196, R161)
  RECORD_NOUNS = { "portfolio_investments" => %w[investment investments], "commitments" => %w[commitment commitments],
                   "payments" => %w[payment payments], "distributions" => %w[distribution distributions],
                   "investor_kycs" => ["KYC record", "KYC records"] }.freeze

  def earlier_words(count, source)
    one, many = RECORD_NOUNS.fetch(source.to_s, %w[record records])
    count.to_i == 1 ? "1 #{one} made before this check started is not checked" : "#{count} #{many} made before this check started are not checked"
  end

  # Full digits, no crore shorthand — the conversion line of a currency check: "₹1,20,00,000", "USD 144,578" (H24)
  def amount_full(value, currency = "INR")
    return "—" if value.nil?

    whole = value.to_d.round(0).to_i
    currency == "INR" ? "₹#{indian_grouping(whole)}" : "#{currency} #{ActiveSupport::NumberHelper.number_to_delimited(whole)}"
  end

  # An exchange rate as written in the working: 83 → "83.00"; a derived 0.01204819 keeps its decimals (H24)
  def rate(value)
    r = value.to_d
    r == r.round(2) ? format("%.2f", r) : r.round(8).to_s("F")
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
