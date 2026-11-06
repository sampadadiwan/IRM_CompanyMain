# ⑤ Evaluates one check for one fund and returns an outcome with the working shown to users.
# Never raises: an unmapped input or blank figure is "Could not check — missing: …" (X24, X29), and an
# unexpected error is could_not_check with the error class (LLD › Error Mapping) — never a pass.
# Percentages are compared as displayed, rounded to 2 decimals (R14, E22).
# Currency (Phase 4): fund figures are in the fund's currency; an amount limit carries its own currency
# (default: the pack's). When they differ the figure is converted at the run-date rate from FxRateResolver
# and the rate is shown in the working; no rate → "Could not check — missing: INR/USD rate for <date>" (H24, X25).
# Worked examples H24, X25, H20, H21, H33, H34, H35, E22, E23, E24, E48–E54, E82, E85, E17, X24, X29, X38, H41, E66 —
# openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceCheckEvaluator
  Outcome = Struct.new(:outcome, :figure, :limit_value, :working, keyword_init: true)

  # A figure-currency → limit-currency conversion at one rate. The rate is quoted limit → figure
  # (USD→INR 83.00), so the figure is divided: ₹1,20,00,000 ÷ 83.00 = USD 144,578 (H24).
  Conversion = Struct.new(:from, :to, :rate, :as_of, :source, keyword_init: true) do
    def call(value)
      value && (value.to_d / rate.to_d)
    end

    # "₹1,20,00,000 ÷ 83.00 = USD 144,578"
    def text(value)
      "#{ComplianceFormat.amount_full(value, from)} ÷ #{ComplianceFormat.rate(rate)} = #{ComplianceFormat.amount_full(call(value), to)}"
    end

    # "Rate: ₹83.00 per USD on 05/11/2026 (manual)" — the working always names the rate it used
    def rate_line
      "Rate: #{from == 'INR' ? '₹' : "#{from} "}#{ComplianceFormat.rate(rate)} per #{to} on #{I18n.l(as_of.to_date)} (#{source})"
    end
  end

  # X25: no accepted rate for the run date
  class MissingRate < StandardError
    attr_reader :label

    def initialize(label)
      @label = label
      super("missing: #{label}")
    end
  end

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
  rescue MissingRate => e
    # X25 — Error case: no INR/USD rate on or before the run date → Could not check, never a pass
    could_not_check("Could not check — missing: #{e.label}", missing: e.label)
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

  # The currency the comparison is made in: the limit's when the figure is converted, else the fund's
  def currency
    conversion ? limit_currency : figure_currency
  end

  # Fund figures (measures) are in the fund's currency; a fund without one falls back to the pack's
  def figure_currency
    @ctx.fund.currency.presence || @ctx.version.currency
  end

  # An amount limit carries a currency, defaulting to the pack's (H9)
  def limit_currency
    @check.dig("limit", "currency").presence || @ctx.version.currency
  end

  # H24 — conversion applies to amount checks with a fixed limit in another currency. A limit expression
  # (pro-rata, H35) is built from the fund's own figures, so it is already in the fund's currency.
  def conversion
    return @conversion if defined?(@conversion)

    @conversion = if unit != "amount" || @check.dig("limit", "expr") || limit_currency == figure_currency
                    nil
                  else
                    resolve_conversion
                  end
  end

  # The run-date rate through FxRateResolver with the fund's accepted sources (manual, market, derived)
  def resolve_conversion
    as_of = @ctx.as_of.to_date
    res = FxRateResolver.lookup(entity_id: @ctx.fund.entity_id, from: limit_currency, to: figure_currency, as_of:,
                                policy: SourcePolicy.for(@ctx.fund))
    raise MissingRate, "#{figure_currency}/#{limit_currency} rate for #{I18n.l(as_of)}" if res.nil?

    Conversion.new(from: figure_currency, to: limit_currency, rate: res.rate, as_of: res.as_of || as_of, source: res.source)
  end

  def fmt(value, u = unit)
    ComplianceFormat.by_unit(value, u, currency)
  end

  # Measure values are always shown in the fund's currency (before any conversion)
  def fmt_fund(value, u)
    ComplianceFormat.by_unit(value, u, figure_currency)
  end

  # Shape 1 — limit on a figure
  def evaluate_limit_check
    fig = @mq.evaluate(@check["figure"])
    limit = limit_value
    lines = measure_lines
    return evaluate_each(fig, limit, lines) if fig.grouped? && @check["each"]

    value, group_label = scalar_value(fig)
    return could_not_check("Could not check — the figure could not be computed (division by zero)") if value.nil?

    lines << "#{"#{group_label}: " if group_label}#{render(@check['figure'], group_id: @worst_group)} = #{fmt_fund(value, unit)}"
    if conversion
      # H24 — the figure converted into the limit's currency, with the rate named
      lines << conversion.rate_line
      lines << conversion.text(value)
      value = conversion.call(value)
    end
    shown = displayed(value)
    ok = self.class.passes?(shown, displayed_limit(limit), cmp)
    lines << "#{fmt(value)} #{ok ? SYMBOLS[cmp] : FAIL_SYMBOLS[cmp]} #{limit_text(limit)} → #{ok ? 'Pass' : 'Breach'}"
    explained = ComplianceWorkingSteps.new(self, fig:, value:, limit:, ok:, group_label:).call
    finish(ok ? "pass" : failing_outcome, shown, displayed_limit(limit), lines,
           message: ok ? nil : "#{fmt(value)} #{FAIL_SYMBOLS[cmp]} #{limit_text(limit)}", largest: group_label, **explained)
  end

  # Read by ComplianceWorkingSteps, which turns this evaluation into the result page's steps (R113)
  public

  attr_reader :check, :ctx, :mq, :worst_group

  def explain_fmt(value, u = unit) = fmt(value, u)
  def explain_fmt_fund(value, u) = fmt_fund(value, u)
  # E197: remedies read in crores (R162)
  def explain_fmt_remedy(value, u = unit) = u == "amount" ? ComplianceFormat.amount_cr(value, currency) : fmt(value, u)
  def explain_fmt_fund_remedy(value) = ComplianceFormat.amount_cr(value, figure_currency)
  def explain_render(expr, group_id: nil) = render(expr, group_id:)
  def explain_limit_text(limit) = limit_text(limit)
  def explain_unit = unit
  def explain_cmp = cmp
  def explain_conversion = conversion

  private

  # "each" — every group must pass; failing groups are listed with their shortfall (E23, E52)
  def evaluate_each(fig, limit, lines)
    lim = displayed_limit(limit)
    raw = fig.groups
    # H24 — each investor's figure converted into the limit's currency
    groups = conversion ? raw.transform_values { |v| conversion.call(v) } : raw
    failing = groups.filter_map do |gid, v|
      next if v.nil? || self.class.passes?(displayed(v), lim, cmp)

      shown = conversion ? "#{conversion.text(raw[gid])} #{FAIL_SYMBOLS[cmp]} #{limit_text(limit)}" : fmt(v)
      { "id" => gid, "label" => fig.labels&.dig(gid) || gid.to_s, "figure" => shown,
        "short" => fmt((limit - v).abs) }
    end.sort_by { |g| g["label"].to_s }
    lines << conversion.rate_line if conversion
    lines << "#{failing.size} of #{fig.groups.size} #{failing.size == 1 ? 'fails' : 'fail'} #{limit_text(limit)}"
    failing.first(ComplianceDocumentCheckQuery::MAX_LISTED).each { |g| lines << "#{g['label']}: #{g['figure']} (short #{g['short']})" }
    worst = if failing.empty?
              nil
            else
              groups.values.compact.public_send(%w[lte lt].include?(cmp) ? :max : :min)
            end
    # One-line verdict for the result page (R113)
    verdict = if failing.empty?
                "All #{fig.groups.size} meet the #{limit_text(limit)} limit."
              else
                "#{failing.size} of #{fig.groups.size} are #{%w[lte lt].include?(cmp) ? 'above' : 'below'} the #{limit_text(limit)} limit."
              end
    finish(failing.empty? ? "pass" : failing_outcome, worst ? displayed(worst) : failing.size, lim, lines,
           failing_groups: failing.first(ComplianceDocumentCheckQuery::MAX_LISTED), failing_count: failing.size, verdict:,
           message: failing.empty? ? nil : "#{failing.size} below the limit")
  end

  # Shape 2 — record has a required, signed, timely document (H22)
  def evaluate_document_check
    res = ComplianceDocumentCheckQuery.call(@check, @ctx)
    # E196 / R161: records before the check's start date, in words (the page links to them)
    lines = ["#{res.ok} of #{res.checked} OK · #{res.failing_count} failing · #{ComplianceFormat.earlier_words(res.earlier, @check['source'])}"]
    # One-line verdict for the result page (R113)
    verdict = if res.failing_count.zero?
                "All #{res.checked} records have their signed document."
              else
                "#{res.failing_count} of #{res.checked} records are missing a signed document or were signed late."
              end
    res.failing.each { |f| lines << "#{f['label']} (#{f['date']}): #{f['problem']}" }
    finish(res.failing_count.zero? ? "pass" : failing_outcome, res.failing_count, 0, lines,
           failing_records: res.failing, checked: res.checked, ok: res.ok, earlier: res.earlier, verdict:,
           source: @check["source"], checks_from: @check["checks_from"],
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
    if conversion
      working["fx"] = { "from" => conversion.from, "to" => conversion.to, "rate" => conversion.rate.to_s, "as_of" => conversion.as_of.to_date.iso8601,
                        "source" => conversion.source }
    end
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
        "#{label} = #{render(m['expr'])} = #{fmt_fund(fig.value, m['unit'] || 'amount')}"
      else
        "#{label} = #{fmt_fund(fig.value, m['unit'] || (m['op'].start_with?('count') ? 'count' : 'amount'))}"
      end
    end
  end

  # Expression with values substituted: "₹72.00 cr ÷ ₹270.00 cr". A nested sub-expression shows its
  # computed value ("lower of ₹7.50 cr and ₹5.00 cr", not "lower of 2.5% × ₹300.00 cr and …" — H34).
  def render(expr, group_id: nil, top: true)
    if !top && expr.is_a?(Array)
      fig = @mq.evaluate(expr)
      return fmt_fund(fig.grouped? ? fig.groups[group_id] : fig.value, "amount")
    end

    case expr
    when Numeric then expr.to_d < 1 ? "#{(expr.to_d * 100).to_s('F').delete_suffix('.0')}%" : fmt_fund(expr, "amount")
    when String
      m = @ctx.measure(expr)
      fig = @mq.value_of(m)
      v = fig.grouped? ? fig.groups[group_id] : fig.value
      fmt_fund(v, m["unit"] || (m["op"].to_s.start_with?("count") ? "count" : "amount"))
    when Array
      op = expr.first.to_s
      args = expr.drop(1).map { |e| render(e, group_id:, top: false) }
      return "lower of #{args.join(' and ')}" if op == "min"
      return "higher of #{args.join(' and ')}" if op == "max"

      args.join(" #{{ '/' => '÷', '*' => '×', '-' => '−', '+' => '+' }[op]} ")
    end
  end
end
