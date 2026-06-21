# See SupportAgentJob for context on how this class is used.
class FundStatsAgent < SupportAgentService
  DESCRIPTION = "Compiles and emails periodic fund statistics, including commitments, stakeholder activity, and portfolio investment updates.".freeze

  LONG_DESCRIPTION = <<~DESC.freeze
    Compiles a comprehensive periodic statistics digest for each fund and emails it
    to configured recipients. Runs against all funds in the entity (or a single fund
    if targeted).

    Stats compiled:
    • Capital Commitments — new commitments in the period vs overall totals.
    • Stakeholder Activity — new investors, LPs, and portfolio companies added.
    • Capital Calls — calls issued and collected amounts in the period.
    • Portfolio Investments — new investments and fair-market values.
    • KYC Records — KYC completion activity in the period.
    • Documents — generated documents in the period.

    The report is sent via email through FundStatsMailer and the full stats payload
    is saved to the SupportAgentReport for review.
  DESC

  step :initialize_agent
  # == Core Functions ==
  step :commitment_stats
  step :stakeholder_stats
  step :call_stats
  step :portfolio_investment_stats
  step :kyc_stats
  step :document_stats
  step :email_stats
  step :generate_progress_reports

  def targets(entity_id)
    Fund.where(entity_id: entity_id)
  end

  def initialize_agent(ctx, target: nil, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :initialize_agent) if report

    super

    ctx[:funds] = if target.is_a?(Fund)
                    Fund.where(id: target.id).includes(:capital_commitments, :capital_calls, :capital_remittances, :capital_distributions, :portfolio_investments)
                  else
                    Fund.where(entity_id: @support_agent.entity_id).includes(:capital_commitments, :capital_calls, :capital_remittances, :capital_distributions, :portfolio_investments)
                  end
    ctx[:period] = @support_agent.json_fields["reporting_period"] || "Month"
    ctx[:effective_date] = Date.end_of_period(ctx[:period])
    Rails.logger.debug { "[#{self.class.name}] Initializing agent" }

    mark_step_success(report, :initialize_agent, message: "Agent initialized") if report
    @support_agent.enabled?
  end

  def commitment_stats(ctx, funds:, effective_date:, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :commitment_stats) if report

    funds.each do |fund|
      ctx[fund.id] ||= {}
      capital_commitments = fund.capital_commitments
      period_capital_commitments = capital_commitments.where(commitment_date: effective_date..)
      ctx[fund.id][:commitment_summary] = {
        period_count: period_capital_commitments.count,
        period_total_amount: Money.new(period_capital_commitments.sum(:committed_amount_cents), fund.currency),
        overall_count: capital_commitments.count,
        overall_total_amount: Money.new(capital_commitments.sum(:committed_amount_cents), fund.currency)
      }
    rescue StandardError => e
      Rails.logger.error { "[#{self.class.name}] Error in commitment_stats: #{e.message}" }
      mark_step_failed(report, :commitment_stats, message: e.message) if report
    end

    mark_step_success(report, :commitment_stats, message: "Processed #{funds.size} fund(s)") if report
  end

  def stakeholder_stats(ctx, effective_date:, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :stakeholder_stats) if report

    stakeholders = @support_agent.entity.investors
    period_stakeholders = stakeholders.where(created_at: effective_date..)
    ctx[:stakeholder_summary] = {
      period_stakeholders: period_stakeholders.count,
      period_lps: period_stakeholders.where(category: "LP").count,
      period_portfolio_companies: period_stakeholders.where(category: "Portfolio Company").count,
      total_stakeholders: stakeholders.count,
      total_lps: stakeholders.where(category: "LP").count,
      total_portfolio_companies: stakeholders.where(category: "Portfolio Company").count
    }

    mark_step_success(report, :stakeholder_stats, message: "Found #{stakeholders.count} stakeholder(s)") if report
  rescue StandardError => e
    Rails.logger.error { "[#{self.class.name}] Error in stakeholder_stats: #{e.message}" }
    mark_step_failed(report, :stakeholder_stats, message: e.message) if report
  end

  def call_stats(ctx, funds:, effective_date:, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :call_stats) if report

    funds.each do |fund|
      ctx[fund.id] ||= {}
      capital_calls = fund.capital_calls
      period_calls = capital_calls.where(call_date: effective_date..)
      ctx[fund.id][:call_summary] = {
        period_count: period_calls.count,
        period_collected_amount: Money.new(period_calls.sum(:collected_amount_cents), fund.currency),
        overall_count: capital_calls.count,
        overall_collected_amount: Money.new(capital_calls.sum(:collected_amount_cents), fund.currency)
      }
    rescue StandardError => e
      Rails.logger.error { "[#{self.class.name}] Error in call_stats: #{e.message}" }
      mark_step_failed(report, :call_stats, message: e.message) if report
    end

    mark_step_success(report, :call_stats, message: "Processed #{funds.size} fund(s)") if report
  end

  def portfolio_investment_stats(ctx, funds:, effective_date:, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :portfolio_investment_stats) if report

    funds.each do |fund|
      ctx[fund.id] ||= {}
      investments = fund.portfolio_investments
      period_investments = investments.where(investment_date: effective_date..)
      ctx[fund.id][:investment_summary] = {
        period_count: period_investments.count,
        period_total_amount: Money.new(period_investments.sum(:amount_cents), fund.currency),
        period_fmv_amount: Money.new(period_investments.sum(:fmv_cents), fund.currency),
        overall_count: investments.count,
        overall_total_amount: Money.new(investments.sum(:amount_cents), fund.currency),
        overall_fmv_amount: Money.new(investments.sum(:fmv_cents), fund.currency)
      }
    rescue StandardError => e
      Rails.logger.error { "[#{self.class.name}] Error in portfolio_investment_stats: #{e.message}" }
      mark_step_failed(report, :portfolio_investment_stats, message: e.message) if report
    end

    mark_step_success(report, :portfolio_investment_stats, message: "Processed #{funds.size} fund(s)") if report
  end

  def kyc_stats(ctx, effective_date:, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :kyc_stats) if report

    kyc_records = @support_agent.entity.investor_kycs
    period_kyc_records = kyc_records.where(created_at: effective_date..)
    ctx[:kyc_summary] = {
      period_count: period_kyc_records.count,
      overall_count: kyc_records.count
    }

    mark_step_success(report, :kyc_stats, message: "Found #{kyc_records.count} KYC record(s)") if report
  rescue StandardError => e
    Rails.logger.error { "[#{self.class.name}] Error in kyc_stats: #{e.message}" }
    mark_step_failed(report, :kyc_stats, message: e.message) if report
  end

  def document_stats(ctx, effective_date:, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :document_stats) if report

    generated_documents = @support_agent.entity.documents.generated
    period_generated_documents = generated_documents.where(created_at: effective_date..)
    ctx[:generated_document_summary] = {
      period_count: period_generated_documents.count,
      overall_count: generated_documents.count
    }

    mark_step_success(report, :document_stats, message: "Found #{generated_documents.count} document(s)") if report
  rescue StandardError => e
    Rails.logger.error { "[#{self.class.name}] Error in document_stats: #{e.message}" }
    mark_step_failed(report, :document_stats, message: e.message) if report
  end

  def email_stats(ctx, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :email_stats) if report

    FundStatsMailer.fund_stats_update(@support_agent, ctx).deliver_now

    mark_step_success(report, :email_stats, message: "Stats email sent") if report
    true
  rescue StandardError => e
    Rails.logger.error { "[#{self.class.name}] Error in email_stats: #{e.message}" }
    mark_step_failed(report, :email_stats, message: e.message) if report
  end

  def generate_progress_reports(ctx, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :generate_progress_reports) if report

    # Save all computed stats into the report's json_fields
    if report
      # Collect all stats from ctx
      stats = {
        stakeholder_summary: ctx[:stakeholder_summary],
        kyc_summary: ctx[:kyc_summary],
        generated_document_summary: ctx[:generated_document_summary]
      }.compact

      # Per-fund stats keyed by fund id
      fund_stats = {}
      ctx[:funds].each do |fund|
        fund_stats[fund.id] = ctx[fund.id] if ctx[fund.id].present?
      end
      stats[:fund_stats] = fund_stats

      report.json_fields = (report.json_fields || {}).merge(stats.deep_stringify_keys)
      report.json_fields_will_change!
      report.save!
    end

    mark_step_success(report, :generate_progress_reports, message: "Report saved") if report

    all_success = report&.json_fields&.dig("steps")&.all? { |s| s["status"] == "success" }
    finalize_report(report, status: all_success ? "ready" : "blocked") if report
    true
  rescue StandardError => e
    Rails.logger.error { "[#{self.class.name}] Error in generate_progress_reports: #{e.message}" }
    mark_step_failed(report, :generate_progress_reports, message: e.message) if report
  end
end
