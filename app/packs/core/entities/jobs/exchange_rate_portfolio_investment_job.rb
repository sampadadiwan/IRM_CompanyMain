class ExchangeRatePortfolioInvestmentJob < ApplicationJob
  queue_as :serial

  def perform(id)
    Chewy.strategy(:sidekiq) do
      @exchange_rate = ExchangeRate.find(id)
      # Find all the portfolio_investments that are in the same currency as the exchange rate
      portfolio_investments = @exchange_rate.entity.portfolio_investments
      portfolio_investments = portfolio_investments.joins(:investment_instrument, :fund).where(investment_instruments: { currency: @exchange_rate.from }).where(funds: { currency: @exchange_rate.to })
      # E29 / E72 — recompute only the funds whose accepted sources include this rate
      portfolio_investments = portfolio_investments.where(fund_id: accepting_fund_ids)

      count = portfolio_investments.count

      # Update the portfolio_investments - this will recompute the FMV based on latest exchange rate
      FxRateResolver.with_cache do
        # Each batch's sold/transferred quantities in two grouped queries, not two SUMs per investment
        PortfolioInvestment.find_each_with_buy_quantities(portfolio_investments) do |portfolio_investment|
          PortfolioInvestmentUpdate.call(portfolio_investment:)
        end
      end

      Rails.logger.debug { "Updated #{count} portfolio_investments due to exchange_rate change" }
    end
    nil
  end

  private

  # Funds of the entity that would use this rate: a fund's own rate → that fund (while it uses its
  # own rates); otherwise every fund whose policy accepts the rate's source.
  def accepting_fund_ids
    funds = Fund.where(entity_id: @exchange_rate.entity_id)
    if @exchange_rate.owner_type == "Fund"
      funds.where(id: @exchange_rate.owner_id).select { |f| f.features.use_own_fx_rates? }.map(&:id)
    else
      funds.select { |f| SourcePolicy.for(f).rate_sources.include?(@exchange_rate.source) }.map(&:id)
    end
  end
end
