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
        # H6: each batch's sold/transferred quantities in two grouped queries, not two SUMs per investment
        PortfolioInvestment.find_each_with_buy_quantities(fund.portfolio_investments) do |portfolio_investment|
          PortfolioInvestmentUpdate.call(portfolio_investment:)
        end
      end
    end
  end
end
