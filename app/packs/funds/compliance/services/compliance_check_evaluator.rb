# ⑤ Evaluates one check for one fund and returns an outcome with the working shown to users.
# Never raises: an unmapped input or blank figure is "Could not check — missing: …" (X24, X29), and an
# unexpected error is could_not_check with the error class (LLD › Error Mapping) — never a pass.
# Percentages are compared as displayed, rounded to 2 decimals (R14, E22).
# Worked examples H20, H21, H33, H34, H35, E22, E23, E24, E48–E54, E82, E85, E17, X24, X29, X38, H41, E66 —
# openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceCheckEvaluator
  Outcome = Struct.new(:outcome, :figure, :limit_value, :working, keyword_init: true)

  SYMBOLS = { "lte" => "≤", "lt" => "<", "gte" => "≥", "gt" => ">", "eq" => "=" }.freeze
  FAIL_SYMBOLS = { "lte" => ">", "lt" => "≥", "gte" => "<", "gt" => "≤", "eq" => "≠" }.freeze

  def self.compare_direction(check)
    check["compare"].presence || "lte"
  end

  # Is limit a stricter than limit b for this comparison? (overrides — X52, E90–E92)
  def self.stricter?(a, b, cmp)
    %w[lte lt].include?(cmp) ? a < b : a > b
  end

  def self.passes?(value, limit, cmp)
    case cmp
    when "lte" then value <= limit
    when "lt" then value < limit
    when "gte" then value >= limit
    when "gt" then value > limit
    when "eq" then value == limit
    end
  end

  # Is a new figure worse than an approved one? (E33, E34)
  def self.worse?(new_value, old_value, cmp)
    return false if new_value.nil? || old_value.nil?

    %w[lte lt eq].include?(cmp) ? new_value > old_value : new_value < old_value
  end

  def self.call(check, context:, override: nil, pending_override: nil, transition_until: nil)
    new(check, context, override:, pending_override:, transition_until:).call
  end

  def initialize(check, context, override:, pending_override:, transition_until:)
    @check = check
    @ctx = context
    @override = override
    @pending_override = pending_override
    @transition_until = transition_until
    @mq = ComplianceMeasureQuery.new(context)
  end

  def call
    case @check["kind"]
    when "record_document" then evaluate_document_check
    when "content" then evaluate_content_check
    else evaluate_limit_check
    end
  rescue ComplianceMeasureQuery::MissingInput => e
    could_not_check("Could not check — missing: #{e.input_label}", missing: e.input_label)
  rescue StandardError => e
    Rails.logger.warn("[Compliance] check #{@check['key']} fund #{@ctx.fund.id}: #{e.class}")
    could_not_check("Could not check — #{e.class.name.demodulize.underscore.humanize}")
  end

  private

  def unit
    @check.dig("limit", "unit").presence || "pct"
  end

  def cmp
    self.class.compare_direction(@check)
  end

  def currency
    @ctx.version.currency
  end

  def fmt(value, u = unit)
    ComplianceFormat.by_unit(value, u, currency)
  end

  # Shape 1 — limit on a figure
  def evaluate_limit_check
    fig = @mq.evaluate(@check["figure"])
    limit = limit_value
    lines = measure_lines
    return evaluate_each(fig, limit, lines) if fig.grouped? && @check["each"]

    value, group_label = scalar_value(fig)
    return could_not_check("Could not check — the figure could not be computed (division by zero)") if value.nil?

    shown = displayed(value)
    lines << "#{"#{group_label}: " if group_label}#{render(@check['figure'], group_id: @worst_group)} = #{fmt(value)}"
    ok = self.class.passes?(shown, displayed_limit(limit), cmp)
    lines << "#{fmt(value)} #{ok ? SYMBOLS[cmp] : FAIL_SYMBOLS[cmp]} #{limit_text(limit)} → #{ok ? 'Pass' : 'Breach'}"
    finish(ok ? "pass" : failing_outcome, shown, displayed_limit(limit), lines,
           message: ok ? nil : "#{fmt(value)} #{FAIL_SYMBOLS[cmp]} #{limit_text(limit)}", largest: group_label)
  end

  # "each" — every group must pass; failing groups are listed with their shortfall (E23, E52)
  def evaluate_each(fig, limit, lines)
    lim = displayed_limit(limit)
    failing = fig.groups.filter_map do |gid, v|
      next if v.nil? || self.class.passes?(displayed(v), lim, cmp)

      { "id" => gid, "label" => fig.labels&.dig(gid) || gid.to_s, "figure" => fmt(v),
        "short" => fmt((limit - v).abs) }
    end.sort_by { |g| g["label"].to_s }
    lines << "#{failing.size} of #{fig.groups.size} #{failing.size == 1 ? 'fails' : 'fail'} #{limit_text(limit)}"
    failing.first(ComplianceDocumentCheckQuery::MAX_LISTED).each { |g| lines << "#{g['label']}: #{g['figure']} (short #{g['short']})" }
    worst = if failing.empty?
              nil
            else
              fig.groups.values.compact.public_send(%w[lte lt].include?(cmp) ? :max : :min)
            end
    finish(failing.empty? ? "pass" : failing_outcome, worst ? displayed(worst) : failing.size, lim, lines,
           failing_groups: failing.first(ComplianceDocumentCheckQuery::MAX_LISTED), failing_count: failing.size,
           message: failing.empty? ? nil : "#{failing.size} below the limit")
  end

  # Shape 2 — record has a required, signed, timely document (H22)
  def evaluate_document_check
    res = ComplianceDocumentCheckQuery.call(@check, @ctx)
    lines = ["#{res.ok} of #{res.checked} OK · #{res.failing_count} failing · #{res.earlier} earlier not checked"]
    res.failing.each { |f| lines << "#{f['label']} (#{f['date']}): #{f['problem']}" }
    finish(res.failing_count.zero? ? "pass" : failing_outcome, res.failing_count, 0, lines,
           failing_records: res.failing, checked: res.checked, ok: res.ok, earlier: res.earlier,
           message: lines.first, unit: "count")
  end

  # Shape 3 — document contents compared with records and lists over confirmed facts (Phase 3).
  # Breach → failing outcome (Warning in a transition); otherwise the worst of Needs review / Pass.
  def evaluate_content_check
    res = ComplianceContentCheck.call(@check, @ctx)
    outcome = res.outcome == "breach" ? failing_outcome : res.outcome
    message = res.failing.size == 1 ? res.failing.first["problem"] : res.lines.first
    finish(outcome, res.figure, 0, res.lines, failing_records: res.failing, message: outcome == "pass" ? nil : message,
                                              unit: "count", **res.extra.symbolize_keys)
  end

  # Grouped figure without "each": the worst group decides (largest for ≤, smallest for ≥)
  def scalar_value(fig)
    return [fig.value, nil] unless fig.grouped?
    return [0.to_d, nil] if fig.groups.empty? # E30: no investments → 0%

    pick = %w[lte lt eq].include?(cmp) ? :max_by : :min_by
    gid, value = fig.groups.compact.public_send(pick) { |_, v| v }
    @worst_group = gid
    [value, gid && (fig.labels&.dig(gid) || gid.to_s)]
  end

  # Override (approved) replaces the pack value; a limit expression is evaluated (pro-rata, H35)
  def limit_value
    return @override.payload_hash["limit"].to_d if @override
    return @check.dig("limit", "value").to_d unless @check.dig("limit", "expr")

    fig = @mq.evaluate(@check.dig("limit", "expr"))
    raise ComplianceMeasureQuery::MissingInput, "limit" if fig.grouped? || fig.value.nil?

    fig.value
  end

  def displayed(value)
    case unit
    when "pct" then ComplianceFormat.pct_value(value)
    when "count" then value.to_d.round(0)
    else value.to_d.round(2)
    end
  end

  # pct limits are entered as percentages (25), amounts in major units — both compared at 2 decimals
  def displayed_limit(limit)
    limit.to_d.round(2)
  end

  def limit_text(limit)
    text = ComplianceFormat.limit(limit, unit, currency)
    return text unless @override

    "#{text} (pack: #{ComplianceFormat.limit(@check.dig('limit', 'value'), unit, currency)})"
  end

  def failing_outcome
    sev = @check["severity"].presence || "breach"
    return "warning" if sev == "breach" && @transition_until

    sev
  end

  def finish(outcome, figure, limit, lines, message: nil, **extra)
    working = { "lines" => lines, "message" => message, "unit" => unit, "currency" => currency }.merge(extra.stringify_keys)
    working["message"] = "In transition until #{I18n.l(@transition_until)}" if outcome == "warning" && @transition_until
    working["override"] = "#{ComplianceFormat.limit(@override.payload_hash['limit'], unit, currency)} (pack: #{ComplianceFormat.limit(@check.dig('limit', 'value'), unit, currency)})" if @override
    working["pending_override"] = "Override pending approval" if @pending_override
    Outcome.new(outcome:, figure:, limit_value: limit, working:)
  end

  def could_not_check(message, missing: nil)
    Outcome.new(outcome: "could_not_check", figure: nil, limit_value: nil,
                working: { "message" => message, "missing" => missing, "lines" => [message] }.compact)
  end

  # Lines for each measure the figure and limit use, leaves first: "Investable funds = ₹300.00 cr − ₹30.00 cr = ₹270.00 cr"
  def measure_lines
    keys = []
    collect = lambda do |expr|
      case expr
      when String
        m = @ctx.measure(expr)
        collect.call(m["expr"]) if m && m["op"] == "expr"
        keys << expr unless keys.include?(expr)
      when Array then expr.drop(1).each { |e| collect.call(e) }
      end
    end
    collect.call(@check["figure"])
    collect.call(@check.dig("limit", "expr")) if @check.dig("limit", "expr")
    keys.filter_map do |k|
      m = @ctx.measure(k)
      fig = @mq.value_of(m)
      next if fig.grouped?

      label = m["label"].presence || k.humanize
      if m["op"] == "expr"
        "#{label} = #{render(m['expr'])} = #{fmt(fig.value, m['unit'] || 'amount')}"
      else
        "#{label} = #{fmt(fig.value, m['unit'] || (m['op'].start_with?('count') ? 'count' : 'amount'))}"
      end
    end
  end

  # Expression with values substituted: "₹72.00 cr ÷ ₹270.00 cr". A nested sub-expression shows its
  # computed value ("lower of ₹7.50 cr and ₹5.00 cr", not "lower of 2.5% × ₹300.00 cr and …" — H34).
  def render(expr, group_id: nil, top: true)
    if !top && expr.is_a?(Array)
      fig = @mq.evaluate(expr)
      return fmt(fig.grouped? ? fig.groups[group_id] : fig.value, "amount")
    end

    case expr
    when Numeric then expr.to_d < 1 ? "#{(expr.to_d * 100).to_s('F').delete_suffix('.0')}%" : fmt(expr, "amount")
    when String
      m = @ctx.measure(expr)
      fig = @mq.value_of(m)
      v = fig.grouped? ? fig.groups[group_id] : fig.value
      fmt(v, m["unit"] || (m["op"].to_s.start_with?("count") ? "count" : "amount"))
    when Array
      op = expr.first.to_s
      args = expr.drop(1).map { |e| render(e, group_id:, top: false) }
      return "lower of #{args.join(' and ')}" if op == "min"
      return "higher of #{args.join(' and ')}" if op == "max"

      args.join(" #{{ '/' => '÷', '*' => '×', '-' => '−', '+' => '+' }[op]} ")
    end
  end
end
