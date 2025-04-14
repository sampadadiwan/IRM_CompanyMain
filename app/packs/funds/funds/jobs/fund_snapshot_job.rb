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

    Rails.logger.debug { "Generating snapshot for #{funds.count} funds" }

    Chewy.strategy(:sidekiq) do
      # Iterate through each fund
      funds.each do |fund|
        Rails.logger.debug { "Creating snapshot for fund: #{fund.name}" }
        # Create a snapshot for the fund
        fund_snapshot = Fund.snapshot(fund)
        fund_snapshot.save(validate: false)

        fund.aggregate_portfolio_investments.each do |api|
          api_snapshot = AggregatePortfolioInvestment.snapshot(api)
          api_snapshot.fund = fund_snapshot
          api_snapshot.save(validate: false)

          api.portfolio_investments.each do |pi|
            pi_snapshot = PortfolioInvestment.snapshot(pi)
            pi_snapshot.aggregate_portfolio_investment = api_snapshot
            pi_snapshot.fund = fund_snapshot
            pi_snapshot.save(validate: false)
          end
        end
      end
    end
  end
end
