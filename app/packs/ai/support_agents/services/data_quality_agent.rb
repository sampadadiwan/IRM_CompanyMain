# frozen_string_literal: true

# Runs nightly integrity checks across a fund's financial data.
#
# DataQualityAgent targets one Fund per run and executes a fixed set of
# deterministic SQL checks. It computes a health score (% of active checks
# passing) and emails a fix-it list to the configured recipients.
#
# json_fields configuration:
#   check_commitment_overflows — "true"/"false" (default true)
#   check_missing_valuations   — "true"/"false" (default true)
#   check_stale_fx_rates       — "true"/"false" (default true)
#   send_report                — "true"/"false" (default true)
#   stale_valuation_days       — integer (default 90)
#   stale_fx_days              — integer (default 30)
#
# @see SupportAgentService
class DataQualityAgent < SupportAgentService
  DESCRIPTION = "Nightly data integrity checks per fund: commitment overflows, stale valuations, stale FX rates. Emails a health score and fix-it list."

  LONG_DESCRIPTION = <<~DESC
    Runs deterministic integrity checks across each fund's financial data on a nightly schedule.
    Targets every Fund in the entity and produces a health score (percentage of active checks passing)
    along with a fix-it list emailed to configured recipients.

    Checks:
    • Commitment Overflows — flags any LP whose total called amount exceeds their commitment.
    • Missing Valuations — identifies portfolio companies without a valuation in the past N days
      (configurable via stale_valuation_days, default 90).
    • Stale FX Rates — flags currencies whose exchange rate hasn't been updated in N days
      (configurable via stale_fx_days, default 30).

    Each check is independently toggleable (check_commitment_overflows, check_missing_valuations,
    check_stale_fx_rates). Email delivery is controlled by send_report. Health score and
    per-check results are stored in json_fields on the SupportAgentReport.
  DESC

  STEP_LABELS = {
    initialize_agent: "Initialize",
    check_commitment_overflows: "Commitment Check",
    check_missing_valuations: "Valuation Check",
    check_stale_fx_rates: "FX Rate Check",
    compute_health_score: "Health Score",
    send_quality_report: "Send Report",
    generate_progress_reports: "Save Report"
  }.freeze

  step :initialize_agent
  step :check_commitment_overflows
  step :check_missing_valuations
  step :check_stale_fx_rates
  step :compute_health_score
  step :send_quality_report
  step :generate_progress_reports

  def targets(entity_id)
    Fund.where(entity_id: entity_id)
  end

  # Human descriptions of the steps each json_fields toggle gates.
  CHECK_TOGGLES = {
    "check_commitment_overflows" => "the commitment overflow check",
    "check_missing_valuations"   => "the missing/stale valuation check",
    "check_stale_fx_rates"       => "the stale FX rate check",
    "send_report"                => "the data quality report email"
  }.freeze

  # The three toggles that actually produce findings (send_report only emails them).
  DATA_CHECK_KEYS = %w[check_commitment_overflows check_missing_valuations check_stale_fx_rates].freeze

  # Setup health check — with all checks off the agent computes a perfect
  # health score from zero checks; blank threshold strings parse to 0 days
  # and flag everything as stale.
  def self.config_issues(support_agent)
    fields = support_agent.json_fields || {}
    issues = missing_toggle_issues(support_agent, CHECK_TOGGLES)

    if DATA_CHECK_KEYS.none? { |k| toggle_on?(support_agent, k) }
      issues << "All data checks are disabled — the agent would report a perfect health score without checking anything."
    end

    # A key that is present but blank parses to 0 days (missing keys use sane defaults)
    %w[stale_valuation_days stale_fx_days].each do |key|
      if fields.key?(key) && fields[key].to_s.strip.blank?
        issues << "'#{key}' is blank — a blank value means 0 days, so everything is flagged stale. Set a number of days or remove the field."
      end
    end

    issues
  end

  private

  # target can be an Entity (run_with_steps single-panel run) or a Fund (scheduled/batch run).
  # ctx[:funds] is always an array so every step can iterate uniformly.
  def initialize_agent(ctx, target:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :initialize_agent) if report
    super
    ctx[:funds]          = target.is_a?(Entity) ? Fund.where(entity_id: target.id) : [target]
    ctx[:entity_id]      = target.is_a?(Entity) ? target.id : target.entity_id
    ctx[:target_model]   = target  # used by generate_progress_reports
    ctx[:issues]         = { commitment_issues: [], valuation_issues: [], fx_issues: [] }
    ctx[:check_results]  = []
    # Per-fund breakdown used by send_quality_report to send correct data per email
    ctx[:fund_data]      = ctx[:funds].each_with_object({}) do |f, h|
      h[f.id] = { issues: { commitment_issues: [], valuation_issues: [], fx_issues: [] }, check_results: [] }
    end
    mark_step_success(report, :initialize_agent) if report
    @support_agent.enabled?
  end

  # Checks whether any LP's called amount exceeds their total commitment.
  #
  # Configurable: check_commitment_overflows — "true"/"false"
  def check_commitment_overflows(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_commitment_overflows) if report

    unless enabled?("check_commitment_overflows")
      ctx[:check_results] << { name: "Commitment Overflows", status: :skipped }
      Rails.logger.debug { "[DataQualityAgent] check_commitment_overflows disabled, skipping." }
      mark_step_skipped(report, :check_commitment_overflows, message: "Disabled") if report
      return true
    end

    total_overflows = 0
    ctx[:funds].each do |fund|
      overflows = fund.capital_commitments.select do |c|
        c.collected_amount_cents.to_i > c.committed_amount_cents.to_i
      end
      items = overflows.map do |c|
        { "name" => c.investor_name.presence || "Commitment ##{c.id}",
          "reason" => "Collected #{c.collected_amount} exceeds committed #{c.committed_amount}" }
      end
      ctx[:issues][:commitment_issues].concat(items)
      ctx[:fund_data][fund.id][:issues][:commitment_issues].concat(items)
      status = overflows.any? ? :fail : :pass
      ctx[:fund_data][fund.id][:check_results] << { name: "Commitment Overflows", status: status, count: (overflows.size if overflows.any?) }
      total_overflows += overflows.size
    end

    if total_overflows > 0
      ctx[:check_results] << { name: "Commitment Overflows", status: :fail, count: total_overflows }
      Rails.logger.warn { "[DataQualityAgent] #{total_overflows} collected > committed overflow(s)" }
      mark_step_success(report, :check_commitment_overflows, message: "#{total_overflows} overflow(s) found", count: total_overflows) if report
    else
      ctx[:check_results] << { name: "Commitment Overflows", status: :pass }
      mark_step_success(report, :check_commitment_overflows, message: "No overflows") if report
    end
    true
  end

  # Checks for portfolio companies with no valuation updated within the configured window.
  #
  # Configurable: check_missing_valuations — "true"/"false"
  #               stale_valuation_days     — integer (default 90)
  def check_missing_valuations(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_missing_valuations) if report

    unless enabled?("check_missing_valuations")
      ctx[:check_results] << { name: "Missing Valuations", status: :skipped }
      Rails.logger.debug { "[DataQualityAgent] check_missing_valuations disabled, skipping." }
      mark_step_skipped(report, :check_missing_valuations, message: "Disabled") if report
      return true
    end

    stale_days = @support_agent.json_fields["stale_valuation_days"]&.to_i || 90
    cutoff = stale_days.days.ago.to_date

    total_stale = 0
    ctx[:funds].each do |fund|
      pc_ids = fund.portfolio_investments.pluck(:portfolio_company_id).uniq
      stale = Investor.where(id: pc_ids).select { |pc| pc.valuations.where(valuation_date: cutoff..).empty? }
      items = stale.map { |pc| { "name" => pc.investor_name, "reason" => "No valuation in the last #{stale_days} days" } }
      ctx[:issues][:valuation_issues].concat(items)
      ctx[:fund_data][fund.id][:issues][:valuation_issues].concat(items)
      status = stale.any? ? :fail : :pass
      ctx[:fund_data][fund.id][:check_results] << { name: "Missing Valuations", status: status, count: (stale.size if stale.any?) }
      total_stale += stale.size
    end

    if total_stale > 0
      ctx[:check_results] << { name: "Missing Valuations", status: :fail, count: total_stale }
      Rails.logger.warn { "[DataQualityAgent] #{total_stale} portfolio company/companies missing recent valuations" }
      mark_step_success(report, :check_missing_valuations, message: "#{total_stale} stale valuation(s)", count: total_stale) if report
    else
      ctx[:check_results] << { name: "Missing Valuations", status: :pass }
      mark_step_success(report, :check_missing_valuations, message: "All valuations current") if report
    end
    true
  end

  # Checks for exchange rates older than the configured threshold for this entity.
  #
  # Configurable: check_stale_fx_rates — "true"/"false"
  #               stale_fx_days        — integer (default 30)
  def check_stale_fx_rates(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_stale_fx_rates) if report

    unless enabled?("check_stale_fx_rates")
      ctx[:check_results] << { name: "Stale FX Rates", status: :skipped }
      Rails.logger.debug { "[DataQualityAgent] check_stale_fx_rates disabled, skipping." }
      mark_step_skipped(report, :check_stale_fx_rates, message: "Disabled") if report
      return true
    end

    stale_days = @support_agent.json_fields["stale_fx_days"]&.to_i || 30
    stale_pairs = ExchangeRate
                  .where(entity_id: ctx[:entity_id], latest: true)
                  .where(updated_at: ...stale_days.days.ago)

    # FX rates are entity-wide — same result for every fund, so propagate to all
    fx_items = stale_pairs.map do |r|
      { "name" => "#{r.from}/#{r.to}",
        "reason" => "Last updated #{r.updated_at.to_date} (#{(Time.zone.today - r.updated_at.to_date).to_i} days ago)" }
    end
    fx_status = stale_pairs.any? ? :fail : :pass

    ctx[:issues][:fx_issues].concat(fx_items)
    ctx[:funds].each do |fund|
      ctx[:fund_data][fund.id][:issues][:fx_issues].concat(fx_items)
      ctx[:fund_data][fund.id][:check_results] << { name: "Stale FX Rates", status: fx_status, count: (stale_pairs.size if stale_pairs.any?) }
    end

    if stale_pairs.any?
      ctx[:check_results] << { name: "Stale FX Rates", status: :fail, count: stale_pairs.size }
      Rails.logger.warn { "[DataQualityAgent] #{stale_pairs.size} stale FX rate(s) for entity #{ctx[:entity_id]}" }
      mark_step_success(report, :check_stale_fx_rates, message: "#{stale_pairs.size} stale pair(s)", count: stale_pairs.size) if report
    else
      ctx[:check_results] << { name: "Stale FX Rates", status: :pass }
      mark_step_success(report, :check_stale_fx_rates, message: "All FX rates current") if report
    end
    true
  end

  # Computes the health score as % of active (non-skipped) checks that passed.
  # Always runs — no flag, pure arithmetic on ctx.
  def compute_health_score(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :compute_health_score) if report
    active = ctx[:check_results].reject { |r| r[:status] == :skipped }
    passing = active.count { |r| r[:status] == :pass }
    ctx[:health_score] = active.any? ? (passing.to_f / active.size * 100).round : 100
    Rails.logger.info { "[DataQualityAgent] Health score: #{ctx[:health_score]}% (#{passing}/#{active.size} checks passing)" }
    mark_step_success(report, :compute_health_score, message: "#{ctx[:health_score]}%") if report
    true
  end

  # Emails the fix-it report to the configured address.
  # When the target is an Entity, sends one consolidated report covering all funds.
  #
  # Configurable: send_report — "true"/"false"
  def send_quality_report(ctx, support_agent:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :send_quality_report) if report

    unless enabled?("send_report")
      Rails.logger.debug { "[DataQualityAgent] send_report disabled, skipping." }
      mark_step_skipped(report, :send_quality_report, message: "Disabled") if report
      return true
    end

    ctx[:funds].each do |fund|
      fd = ctx[:fund_data][fund.id]
      active  = fd[:check_results].reject { |r| r[:status] == :skipped }
      passing = active.count { |r| r[:status] == :pass }
      fund_ctx = {
        issues:        fd[:issues],
        check_results: fd[:check_results],
        health_score:  active.any? ? (passing.to_f / active.size * 100).round : 100
      }
      DataQualityMailer.quality_report(support_agent, fund, fund_ctx).deliver_now
      Rails.logger.info { "[DataQualityAgent] Quality report sent for Fund #{fund.id}" }
    end
    mark_step_success(report, :send_quality_report, message: "#{ctx[:funds].size} report(s) emailed") if report
    true
  end

  def generate_progress_reports(ctx, support_agent:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :generate_progress_reports) if report
    super(ctx, model: ctx[:target_model], support_agent: support_agent)
    mark_step_success(report, :generate_progress_reports, message: "Report saved") if report
    finalize_report(report, status: :ready) if report
  end
end
