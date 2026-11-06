# ⑧ Plain-words reading of an AI draft, field by field (AD spec: "Plain-words review"):
#   figure "largest investment cost per sector" · divided by "investable funds" · limit "≤ 15%" · source "LPA cl. 8.2"
# Worked examples H37, H39, E57 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
module ComplianceCheckDraftWords
  OPS = { "sum" => "total", "count" => "number of", "count_distinct" => "number of different",
          "max" => "largest", "min" => "smallest" }.freeze
  FILTER_WORDS = { "eq" => "is", "ne" => "is not", "gt" => "above", "gte" => "at least", "lt" => "below",
                   "lte" => "at most", "in" => "in", "not_in" => "not in" }.freeze
  TRIGGERS = { "on_demand" => "On demand", "quarterly" => "Every quarter", "half_yearly" => "Every half year",
               "yearly" => "Every year" }.freeze

  module_function

  # A draft part: an existing measure ("investable funds"; grouped ones read "largest …") or a new one
  def part(version, part)
    return "—" unless part.is_a?(Hash)

    if part["measure"].present?
      measure = version&.measures&.detect { |m| m["key"] == part["measure"] }
      return part["measure"].to_s.humanize.downcase if measure.nil?

      label = (measure["label"].presence || ComplianceDescriber.measure(version, measure["key"])).to_s.downcase
      return measure["group_by"].present? ? "largest #{label}" : label
    end
    new_measure(part)
  end

  def new_measure(part)
    op = OPS[part["op"].to_s] || part["op"].to_s
    text = [op, part["field"].to_s.humanize(capitalize: false).presence, "of", part["source"].to_s.humanize.downcase].compact.join(" ")
    text = "largest #{text} per #{part['group_by']}" if part["group_by"].present?
    filters = Array(part["filters"]).filter_map do |f|
      next unless f.is_a?(Hash)

      "#{f['field'].to_s.humanize(capitalize: false)} #{FILTER_WORDS[f['op'].to_s] || f['op']} #{Array(f['value']).join(', ')}"
    end
    filters.any? ? "#{text} where #{filters.join(' and ')}" : text
  end

  def limit(draft, currency = "INR")
    return "—" if draft["limit_value"].nil?

    "#{ComplianceCheckEvaluator::SYMBOLS[draft['compare'].presence || 'lte']} " \
      "#{ComplianceFormat.limit(draft['limit_value'], draft['limit_unit'].presence || 'pct', currency)}"
  end

  def trigger(draft)
    TRIGGERS[draft["duty_trigger"].to_s] || TRIGGERS["on_demand"]
  end
end
