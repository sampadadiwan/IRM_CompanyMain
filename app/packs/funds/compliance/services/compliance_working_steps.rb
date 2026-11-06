# ⑤ Turns one limit-check evaluation into the result page's explanation, computed at run time and stored
# in the result's working (results are immutable, so the page never re-queries figures — R113):
#   verdict — one sentence: "Ace Limited is 41.91% of investable funds — above the 25.00% limit."
#   steps   — numbered: every measure the figure uses (leaves first), the figure, the limit and the result,
#             each with how it is calculated, its value and where it comes from (records / Setup)
#   remedy  — for a ratio against a % limit: what gets the figure back within the limit (or the headroom)
#   others  — the next largest groups (e.g. investees) with their share and headroom
# Worked example (business-rules shared setup): Acme ₹72.00 cr ÷ investable ₹270.00 cr = 26.67% > 25%
# → reduce Acme to ₹67.50 cr (₹4.50 cr less) or raise investable funds to ₹288.00 cr (E141).
class ComplianceWorkingSteps
  OTHERS = 5

  def initialize(evaluator, fig:, value:, limit:, ok:, group_label:)
    @ev = evaluator
    @fig = fig
    @value = value
    @limit = limit
    @ok = ok
    @group_label = group_label
  end

  def call
    steps = measure_steps
    # A figure that is one measure is already its own step — never restate "₹2.00 cr = ₹2.00 cr"
    steps << figure_step unless figure_expr.is_a?(String)
    steps.concat(limit_steps) if check.dig("limit", "expr")
    steps << rate_step if @ev.explain_conversion
    steps << result_step
    steps.each_with_index { |s, i| s["n"] = i + 1 }
    { "verdict" => verdict, "steps" => steps, "remedy" => remedy || gap_remedy, "others" => others }.compact
  rescue StandardError => e
    # The explanation is extra: a failure here never changes the result
    Rails.logger.warn("[Compliance] working steps #{check['key']}: #{e.class}")
    {}
  end

  private

  def check = @ev.check
  def ctx = @ev.ctx
  def mq = @ev.mq
  def unit = @ev.explain_unit

  def figure_expr = check["figure"]

  # ["/", numerator, denominator] — the shape of share-of-total checks (concentration)
  def ratio?
    figure_expr.is_a?(Array) && figure_expr.first == "/" && figure_expr.size == 3 && unit == "pct"
  end

  def numerator_value
    f = mq.evaluate(figure_expr[1])
    f.grouped? ? f.groups[@ev.worst_group] : f.value
  end

  def denominator_value
    f = mq.evaluate(figure_expr[2])
    f.grouped? ? nil : f.value
  end

  def denominator_label
    key = figure_expr[2]
    key.is_a?(String) ? (ctx.measure(key)&.dig("label").presence || key.humanize) : "the total"
  end

  # Every measure the figure and limit use, leaves first (same walk as the evaluator's measure lines)
  def measure_steps
    keys = []
    collect = lambda do |expr|
      case expr
      when String
        m = ctx.measure(expr)
        collect.call(m["expr"]) if m && m["op"] == "expr"
        keys << expr unless keys.include?(expr)
      when Array then expr.drop(1).each { |e| collect.call(e) }
      end
    end
    collect.call(figure_expr)
    collect.call(check.dig("limit", "expr")) if check.dig("limit", "expr")
    # A limit that is one named measure is shown by limit_steps, part by part — not twice
    keys.delete(limit_measure_key) if limit_measure_key
    keys.filter_map { |k| measure_step(k) }
  end

  # "required_interest_cat12" when the limit is one worked-out measure
  def limit_measure_key
    expr = check.dig("limit", "expr")
    expr.is_a?(String) && ctx.measure(expr)&.dig("op") == "expr" ? expr : nil
  end

  def measure_step(key)
    m = ctx.measure(key)
    return nil if m.nil?

    fig = mq.value_of(m)
    label = m["label"].presence || key.humanize
    u = m["unit"] || (m["op"].to_s.start_with?("count") ? "count" : "amount")
    if fig.grouped?
      gid = @ev.worst_group
      return nil if gid.nil? || fig.groups[gid].nil?

      { "label" => "#{label} — #{@group_label}", "calc" => "The largest of #{fig.groups.size}", "value" => @ev.explain_fmt_fund(fig.groups[gid], u),
        "help" => "Grouped per #{m['group_by']}; the check tests the largest one", "source" => source_for(m) }
    else
      calc = m["op"] == "expr" ? @ev.explain_render(m["expr"]) : calc_for(m)
      { "label" => label, "calc" => calc, "value" => @ev.explain_fmt_fund(fig.value, u), "help" => help_for(m), "source" => source_for(m) }
    end
  end

  def calc_for(measure)
    case measure["op"]
    when "input" then "Entered in Setup"
    when "count", "count_distinct" then "Number of #{measure['source'].to_s.humanize.downcase}"
    else "Total #{measure['field']} of #{measure['source'].to_s.humanize.downcase}"
    end
  end

  def help_for(measure)
    case measure["op"]
    when "input" then "A figure your firm enters once per fund in Compliance › Setup"
    when "expr" then "Worked out from the figures above"
    else "Added up from this fund's #{measure['source'].to_s.humanize.downcase} in CapHive as of the run date"
    end
  end

  # Where a figure comes from, for the page's Source link: CapHive records of the fund, or Setup
  def source_for(measure)
    if measure["op"] == "input"
      label = ctx.input(measure["input"])&.dig("label").presence || measure["input"].to_s.humanize
      { "kind" => "setup", "label" => "Setup › #{label}" }
    elsif measure["source"].present?
      { "kind" => measure["source"], "label" => "#{measure['source'].to_s.humanize} of this fund#{group_filter_text(measure)}" }
    end
  end

  # " — investors in Sponsor/manager" for a measure filtered to an investor group input
  def group_filter_text(measure)
    filter = Array(measure["filters"]).detect { |f| f[0] == "investor_group" }
    return "" unless filter

    groups = Array(filter[2]).map { |key| ctx.input(key)&.dig("label").presence || key.to_s.humanize }.join(", ")
    filter[1] == "not_in" ? " — investors not in #{groups}" : " — investors in #{groups}"
  end

  def figure_step
    { "label" => check["name"].presence || check["key"].humanize, "calc" => @ev.explain_render(figure_expr, group_id: @ev.worst_group),
      "value" => @ev.explain_fmt(@value), "help" => "The figure this check tests" }
  end

  # A limit worked out from the fund's figures (H34, H35): each part, then the required figure.
  # ["min", ["*", 0.025, "corpus"], 50000000] → "2.5% of Corpus", "Fixed amount", "The lower of …"
  def limit_steps
    expr = check.dig("limit", "expr")
    label = upper_limit? ? "Limit" : "Required"
    # A named measure: show its own expression, under its own label ("Required continuing interest")
    if limit_measure_key
      measure = ctx.measure(limit_measure_key)
      expr = measure["expr"]
      label = measure["label"].presence || label
    end
    if expr.is_a?(Array) && %w[min max].include?(expr.first)
      parts = expr.drop(1).map { |part| limit_part_step(part) }
      which = expr.first == "min" ? "lower" : "higher"
      parts + [{ "label" => label, "calc" => "The #{which} of #{parts.pluck('label').join(' and ')}",
                 "value" => @ev.explain_fmt(@limit), "help" => "The pack takes the #{which} of these as the limit" }]
    else
      [{ "label" => label, "calc" => @ev.explain_render(expr), "value" => @ev.explain_fmt(@limit),
         "help" => "Worked out from the fund's own figures above" }]
    end
  end

  def limit_part_step(part)
    if part.is_a?(Numeric)
      { "label" => "Fixed amount", "calc" => "Set by the pack", "value" => @ev.explain_fmt_fund(part, "amount"),
        "help" => "A fixed figure written into the rule" }
    else
      { "label" => describe(part), "calc" => @ev.explain_render(part), "value" => @ev.explain_fmt_fund(mq.evaluate(part).value, "amount"),
        "help" => "Part of the limit, worked out from the fund's figures" }
    end
  end

  # ["*", 0.025, "corpus"] → "2.5% of Corpus"; anything else → its rendered expression
  def describe(expr)
    if expr.is_a?(Array) && expr.first == "*" && expr.size == 3 && expr[1].is_a?(Numeric) && expr[2].is_a?(String)
      "#{(expr[1].to_d * 100).to_s('F').delete_suffix('.0')}% of #{ctx.measure(expr[2])&.dig('label').presence || expr[2].humanize}"
    else
      @ev.explain_render(expr)
    end
  end

  # The figure in words: its measure's label, else the check's name
  def subject_label
    return @group_label if @group_label.present?

    figure_expr.is_a?(String) ? (ctx.measure(figure_expr)&.dig("label").presence || figure_expr.humanize) : (check["name"].presence || check["key"].humanize)
  end

  # Amount and count limits: the gap to close, or the room left (e.g. "needs ₹3.00 cr more (₹5.00 cr − ₹2.00 cr)")
  def gap_remedy
    return nil if ratio? || @ev.explain_conversion || %w[amount count].exclude?(unit)

    gap = (@limit.to_d - @value.to_d).abs
    gap_text = @ev.explain_fmt(gap)
    value_text = @ev.explain_fmt(@value)
    limit_text = @ev.explain_fmt(@limit)
    text = if @ok
             "#{subject_label} is #{gap_text} #{upper_limit? ? 'below' : 'above'} the limit."
           elsif upper_limit?
             "Reduce #{subject_label.downcase_first} by #{gap_text} (#{value_text} − #{limit_text})."
           else
             "#{subject_label} needs #{gap_text} more (#{limit_text} − #{value_text})."
           end
    { "kind" => @ok ? "headroom_text" : "gap", "text" => text, "amount" => gap_text }
  end

  def rate_step
    c = @ev.explain_conversion
    { "label" => "Exchange rate", "calc" => c.rate_line, "value" => c.text(@value), "help" => "Fund figures are converted into the limit's currency at the run-date rate" }
  end

  def result_step
    sym = @ok ? ComplianceCheckEvaluator::SYMBOLS[@ev.explain_cmp] : ComplianceCheckEvaluator::FAIL_SYMBOLS[@ev.explain_cmp]
    { "label" => "Limit and result", "calc" => "#{@ev.explain_fmt(@value)} #{sym} #{@ev.explain_limit_text(@limit)}",
      "value" => @ok ? "Pass" : "Breach", "final" => true,
      "help" => "The pack's limit; an approved stricter override for this fund replaces it" }
  end

  def upper_limit?
    %w[lte lt eq].include?(@ev.explain_cmp)
  end

  def verdict
    subject = subject_label
    position = if upper_limit?
                 @ok ? "within" : "above"
               else
                 @ok ? "meets" : "below"
               end
    of = ratio? ? " of #{denominator_label.downcase}" : ""
    "#{subject} is #{@ev.explain_fmt(@value)}#{of} — #{position} the #{@ev.explain_limit_text(@limit)} limit."
  end

  # Ratio against an upper % limit: reduce the numerator, or raise the denominator; on a pass, the headroom
  def remedy
    return nil unless ratio? && upper_limit?

    num = numerator_value
    den = denominator_value
    return nil if num.nil? || den.nil? || den.zero? || @limit.to_d.zero?

    share = @limit.to_d / 100
    cap = share * den
    subject = @group_label.presence || "the figure"
    if @ok
      { "kind" => "headroom", "amount" => @ev.explain_fmt_fund(cap - num, "amount"),
        "pts" => "#{format('%.2f', (@limit.to_d - ComplianceFormat.pct_value(@value)).round(2))} pts", "subject" => subject }
    else
      { "kind" => "breach", "subject" => subject, "reduce_to" => @ev.explain_fmt_fund(cap, "amount"),
        "reduce_by" => @ev.explain_fmt_fund(num - cap, "amount"), "raise_label" => denominator_label,
        "raise_to" => @ev.explain_fmt_fund(num / share, "amount"),
        "over_pts" => "#{format('%.2f', (ComplianceFormat.pct_value(@value) - @limit.to_d).round(2))} pts" }
    end
  end

  # "₹47.50 cr" of room, or "₹4.50 cr over" when past the limit
  def headroom_text(room)
    room.negative? ? "#{@ev.explain_fmt_fund(-room, 'amount')} over" : @ev.explain_fmt_fund(room, "amount")
  end

  # The next largest groups with their share and headroom (who is closest to the limit)
  def others
    return nil unless ratio?

    f = mq.evaluate(figure_expr[1])
    den = denominator_value
    return nil unless f.grouped? && den.present? && !den.zero?

    share = @limit.to_d / 100
    f.groups.compact.sort_by { |_, v| -v }.first(OTHERS).map do |gid, v|
      { "label" => f.labels&.dig(gid) || gid.to_s, "value" => @ev.explain_fmt_fund(v, "amount"),
        "share" => @ev.explain_fmt(v / den, "pct"), "headroom" => headroom_text((share * den) - v) }
    end
  end
end
