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
  DESCRIPTION = "Nightly data integrity checks per fund: commitment overflows, stale valuations, stale FX rates. Emails a health score and fix-it list.".freeze

  LONG_DESCRIPTION = <<~DESC.freeze
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
    initialize_agent:             "Initialize",
    check_commitment_overflows:   "Commitment Check",
    check_missing_valuations:     "Valuation Check",
    check_stale_fx_rates:         "FX Rate Check",
    compute_health_score:         "Health Score",
    send_quality_report:          "Send Report",
    generate_progress_reports:    "Save Report"
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

  private

  def initialize_agent(ctx, target:, **)
    super
    ctx[:fund] = target
    ctx[:issues] = { commitment_issues: [], valuation_issues: [], fx_issues: [] }
    ctx[:check_results] = []
    @support_agent.enabled?
  end

  # Checks whether any LP's called amount exceeds their total commitment.
  #
  # Configurable: check_commitment_overflows — "true"/"false"
  def check_commitment_overflows(ctx, fund:, **)
    unless enabled?("check_commitment_overflows")
      ctx[:check_results] << { name: "Commitment Overflows", status: :skipped }
      Rails.logger.debug { "[DataQualityAgent] check_commitment_overflows disabled, skipping." }
      return true
    end

    overflows = fund.capital_commitments.select { |c|
      c.collected_amount_cents.to_i > c.committed_amount_cents.to_i
    }

    if overflows.any?
      failed = overflows.map { |c|
        {
          "name"   => c.investor_name.presence || "Commitment ##{c.id}",
          "reason" => "Collected #{c.collected_amount} exceeds committed #{c.committed_amount}"
        }
      }
      ctx[:issues][:commitment_issues].concat(failed)
      ctx[:check_results] << { name: "Commitment Overflows", status: :fail, count: overflows.size }
      Rails.logger.warn { "[DataQualityAgent] #{overflows.size} collected > committed overflow(s) in Fund #{fund.id}" }
    else
      ctx[:check_results] << { name: "Commitment Overflows", status: :pass }
    end
    true
  end

  # Checks for portfolio companies with no valuation updated within the configured window.
  #
  # Configurable: check_missing_valuations — "true"/"false"
  #               stale_valuation_days     — integer (default 90)
  def check_missing_valuations(ctx, fund:, **)
    unless enabled?("check_missing_valuations")
      ctx[:check_results] << { name: "Missing Valuations", status: :skipped }
      Rails.logger.debug { "[DataQualityAgent] check_missing_valuations disabled, skipping." }
      return true
    end

    stale_days = @support_agent.json_fields["stale_valuation_days"]&.to_i || 90
    cutoff = stale_days.days.ago.to_date

    # Portfolio companies are Investor records reachable via portfolio_investments on this fund
    portfolio_company_ids = fund.portfolio_investments.pluck(:portfolio_company_id).uniq
    stale = Investor.where(id: portfolio_company_ids).select { |pc|
      pc.valuations.where("valuation_date >= ?", cutoff).empty?
    }

    if stale.any?
      ctx[:issues][:valuation_issues].concat(
        stale.map { |pc|
          { "name" => pc.investor_name, "reason" => "No valuation in the last #{stale_days} days" }
        }
      )
      ctx[:check_results] << { name: "Missing Valuations", status: :fail, count: stale.size }
      Rails.logger.warn { "[DataQualityAgent] #{stale.size} portfolio company/companies missing recent valuations in Fund #{fund.id}" }
    else
      ctx[:check_results] << { name: "Missing Valuations", status: :pass }
    end
    true
  end

  # Checks for exchange rates older than the configured threshold for this entity.
  #
  # Configurable: check_stale_fx_rates — "true"/"false"
  #               stale_fx_days        — integer (default 30)
  def check_stale_fx_rates(ctx, fund:, **)
    unless enabled?("check_stale_fx_rates")
      ctx[:check_results] << { name: "Stale FX Rates", status: :skipped }
      Rails.logger.debug { "[DataQualityAgent] check_stale_fx_rates disabled, skipping." }
      return true
    end

    stale_days = @support_agent.json_fields["stale_fx_days"]&.to_i || 30
    stale_pairs = ExchangeRate
      .where(entity_id: fund.entity_id, latest: true)
      .where("updated_at < ?", stale_days.days.ago)

    if stale_pairs.any?
      ctx[:issues][:fx_issues].concat(
        stale_pairs.map { |r|
          {
            "name"   => "#{r.from}/#{r.to}",
            "reason" => "Last updated #{r.updated_at.to_date} (#{(Date.today - r.updated_at.to_date).to_i} days ago)"
          }
        }
      )
      ctx[:check_results] << { name: "Stale FX Rates", status: :fail, count: stale_pairs.size }
      Rails.logger.warn { "[DataQualityAgent] #{stale_pairs.size} stale FX rate(s) for entity #{fund.entity_id}" }
    else
      ctx[:check_results] << { name: "Stale FX Rates", status: :pass }
    end
    true
  end

  # Computes the health score as % of active (non-skipped) checks that passed.
  # Always runs — no flag, pure arithmetic on ctx.
  def compute_health_score(ctx, **)
    active = ctx[:check_results].reject { |r| r[:status] == :skipped }
    passing = active.count { |r| r[:status] == :pass }
    ctx[:health_score] = active.any? ? (passing.to_f / active.size * 100).round : 100
    Rails.logger.info { "[DataQualityAgent] Health score: #{ctx[:health_score]}% (#{passing}/#{active.size} checks passing)" }
    true
  end

  # Emails the fix-it report to the configured address.
  #
  # Configurable: send_report — "true"/"false"
  def send_quality_report(ctx, fund:, support_agent:, **)
    unless enabled?("send_report")
      Rails.logger.debug { "[DataQualityAgent] send_report disabled, skipping." }
      return true
    end

    DataQualityMailer.quality_report(support_agent, fund, ctx).deliver_now
    Rails.logger.info { "[DataQualityAgent] Quality report queued for Fund #{fund.id}" }
    true
  end

  def generate_progress_reports(ctx, fund:, support_agent:, **)
    super(ctx, model: fund, support_agent: support_agent)
  end
end
