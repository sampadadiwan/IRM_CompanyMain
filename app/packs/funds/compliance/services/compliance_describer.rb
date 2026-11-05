# ① Plain-words description of a measure or check, shown in the Rule Library and on drafts (H3):
#   ["min", ["*", 0.025, "corpus"], 50000000] → "lower of 2.5% of corpus and ₹5.00 cr"
module ComplianceDescriber
  module_function

  def measure(version, key)
    m = version.measures.detect { |x| x["key"] == key }
    return key.to_s.humanize.downcase if m.nil?
    return expr(version, m["expr"]) if m["op"] == "expr"

    base = { "sum" => "total", "count" => "count", "count_distinct" => "number of", "max" => "largest", "min" => "smallest" }[m["op"]]
    return m["label"].to_s.downcase if base.nil?

    text = "#{base} #{m['field']} of #{m['source'].to_s.humanize.downcase}"
    m["group_by"].present? ? "#{text} per #{m['group_by']}" : text
  end

  def expr(version, node, currency = version.currency)
    case node
    when Numeric then node.to_d < 1 ? "#{(node.to_d * 100).to_s('F').delete_suffix('.0')}%" : ComplianceFormat.amount(node, currency)
    when String then (version.measures.detect { |x| x["key"] == node }&.dig("label") || node.humanize).downcase
    when Array
      op = node.first.to_s
      args = node.drop(1)
      case op
      when "min" then "lower of #{args.map { |a| expr(version, a, currency) }.join(' and ')}"
      when "max" then "higher of #{args.map { |a| expr(version, a, currency) }.join(' and ')}"
      when "*"
        pct, other = args.partition { |a| a.is_a?(Numeric) && a < 1 }
        pct.any? ? "#{expr(version, pct.first, currency)} of #{other.map { |a| expr(version, a, currency) }.join(' × ')}" : args.map { |a| expr(version, a, currency) }.join(" × ")
      else args.map { |a| expr(version, a, currency) }.join(" #{{ '/' => '÷', '-' => '−', '+' => '+' }[op]} ")
      end
    end
  end
end
