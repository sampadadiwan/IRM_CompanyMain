# See SupportAgentJob for context on how this class is used.
class FundStatsAgent < SupportAgentService
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
    Entity.where(id: entity_id)
  end

  def initialize_agent(ctx, **)
    super
    ctx[:funds] = Fund.where(entity_id: @support_agent.entity_id).includes(:capital_commitments, :capital_calls, :capital_remittances, :capital_distributions, :portfolio_investments)
    ctx[:period] = @support_agent.json_fields["reporting_period"] || "Month"
    ctx[:effective_date] = Date.end_of_period(ctx[:period])
    Rails.logger.debug { "[#{self.class.name}] Initializing agent" }
    @support_agent.enabled?
  end

  def commitment_stats(ctx, funds:, effective_date:, **)
    # Analyze capital commitments for the fund
    funds.each do |fund|
      ctx[fund.name.to_s] ||= {}
      capital_commitments = fund.capital_commitments
      period_capital_commitments = capital_commitments.where(commitment_date: effective_date..)
      ctx[fund.name.to_s][:commitment_summary] = {
        period_count: period_capital_commitments.count,
        period_total_amount: Money.new(period_capital_commitments.sum(:committed_amount_cents), fund.currency),
        overall_count: capital_commitments.count,
        overall_total_amount: Money.new(capital_commitments.sum(:committed_amount_cents), fund.currency)
      }
    end
  end

  def stakeholder_stats(ctx, effective_date:, **)
    # Analyze stakeholders for the fund
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
  end

  def call_stats(ctx, funds:, effective_date:, **)
    # Analyze capital calls for the fund
    funds.each do |fund|
      ctx[fund.name.to_s] ||= {}
      capital_calls = fund.capital_calls
      period_calls = capital_calls.where(call_date: effective_date..)
      ctx[fund.name.to_s][:call_summary] = {
        period_count: period_calls.count,
        period_collected_amount: Money.new(period_calls.sum(:collected_amount_cents), fund.currency),
        overall_count: capital_calls.count,
        overall_collected_amount: Money.new(capital_calls.sum(:collected_amount_cents), fund.currency)
      }
    end
  end

  def portfolio_investment_stats(ctx, funds:, effective_date:, **)
    # Analyze portfolio investments for the fund
    funds.each do |fund|
      ctx[fund.name.to_s] ||= {}
      investments = fund.portfolio_investments
      period_investments = investments.where(investment_date: effective_date..)
      ctx[fund.name.to_s][:investment_summary] = {
        period_count: period_investments.count,
        period_total_amount: Money.new(period_investments.sum(:amount_cents), fund.currency),
        period_fmv_amount: Money.new(period_investments.sum(:fmv_cents), fund.currency),
        overall_count: investments.count,
        overall_total_amount: Money.new(investments.sum(:amount_cents), fund.currency),
        overall_fmv_amount: Money.new(investments.sum(:fmv_cents), fund.currency)
      }
    end
  end

  def kyc_stats(ctx, effective_date:, **)
    kyc_records = @support_agent.entity.investor_kycs
    period_kyc_records = kyc_records.where(created_at: effective_date..)
    ctx[:kyc_summary] = {
      period_count: period_kyc_records.count,
      overall_count: kyc_records.count
    }
  end

  def document_stats(ctx, effective_date:, **)
    generated_documents = @support_agent.entity.documents.generated
    period_generated_documents = generated_documents.where(created_at: effective_date..)
    ctx[:generated_document_summary] = {
      period_count: period_generated_documents.count,
      overall_count: generated_documents.count
    }
  end

  def email_stats(ctx, **)
    FundStatsMailer.fund_stats_update(@support_agent, ctx).deliver_now
    true
  end

  def generate_progress_reports(ctx, **)
    FundStatsMailer.fund_stats_update(@support_agent, ctx).deliver_now
    true
  end
end
