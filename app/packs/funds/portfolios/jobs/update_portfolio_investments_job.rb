class UpdatePortfolioInvestmentsJob < ApplicationJob
  queue_as :serial

  def perform(portfolio_investment_ids)
    Chewy.strategy(:sidekiq) do
      portfolio_investments = PortfolioInvestment.where(id: portfolio_investment_ids)
      count = portfolio_investments.count

      # Update the portfolio_investments - this will recompute the numbers
      portfolio_investments.each do |portfolio_investment|
        PortfolioInvestmentUpdate.call(portfolio_investment:)
      end

      Rails.logger.debug { "Updated #{count} portfolio_investments due to valuation deletion" }
    end
    nil
  end
end
