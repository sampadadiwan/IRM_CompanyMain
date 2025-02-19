class ExchangeRatePortfolioInvestmentJob < ApplicationJob
  queue_as :serial

  def perform(id)
    Chewy.strategy(:sidekiq) do
      @exchange_rate = ExchangeRate.find(id)
      # Find all the portfolio_investments that are in the same currency as the exchange rate
      portfolio_investments = @exchange_rate.entity.portfolio_investments
      portfolio_investments = portfolio_investments.joins(:investment_instrument).where(investment_instruments: { currency: @exchange_rate.from })

      count = portfolio_investments.count

      # Update the portfolio_investments - this will recompute the FMV based on latest exchange rate
      portfolio_investments.each do |portfolio_investment|
        PortfolioInvestmentUpdate.call(portfolio_investment:)
      end

      Rails.logger.debug { "Updated #{count} portfolio_investments due to exchange_rate change" }
    end
    nil
  end
end
