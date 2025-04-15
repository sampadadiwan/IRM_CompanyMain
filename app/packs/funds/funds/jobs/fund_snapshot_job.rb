class FundSnapshotJob < ApplicationJob
  queue_as :low

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(fund_id: nil)
    funds =
      if fund_id
        # Fetch the fund with the given fund_id
        Fund.where(id: fund_id)
      else
        # Fetch all funds with the permission to enable snapshots
        Fund.joins(:entity).merge(Entity.where_permissions(:enable_snapshots))
      end

    Chewy.strategy(:sidekiq) do
      # Iterate through each fund
      funds.each do |fund|
        # Create a snapshot for the fund
        FundSnapshot.snapshot(fund)

        # Iterate through each aggregate portfolio investment of the fund
        fund.aggregate_portfolio_investments.each do |api|
          # Create a snapshot for the aggregate portfolio investment
          AggregatePortfolioInvestmentSnapshot.snapshot(api)

          # Iterate through each portfolio investment within the aggregate portfolio investment
          api.portfolio_investments.each do |pi|
            # Create a snapshot for the portfolio investment
            PortfolioInvestmentSnapshot.snapshot(pi)
          end
        end
      end
    end
  end
end
