# Recomputes a fund's current fair values after the fund changes which rate or price sources it
# accepts (FundEnabled). Only fair-value style figures move; booked commitments, calls,
# remittances and distributions keep the rate recorded when they were booked.
# Worked example E31 — openspec/changes/fund-market-data/business-rules.md
class FundFairValueRecomputeJob < ApplicationJob
  queue_as :low

  def perform(fund_id)
    fund = Fund.find_by(id: fund_id)
    return unless fund

    Chewy.strategy(:sidekiq) do
      # Batched: a fund can hold many portfolio investments
      FxRateResolver.with_cache do
        fund.portfolio_investments.find_each do |portfolio_investment|
          PortfolioInvestmentUpdate.call(portfolio_investment:)
        end
      end
    end
  end
end
