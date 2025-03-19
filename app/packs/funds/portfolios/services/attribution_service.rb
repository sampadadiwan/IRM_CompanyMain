class AttributionService
  def initialize(portfolio_investment)
    @portfolio_investment = portfolio_investment
  end

  def setup_attribution
    # Allocate only sells, and make sure its not already been allocated
    if @portfolio_investment.sell? && @portfolio_investment.portfolio_attributions.count.zero?
      # Sell quantity is negative
      allocatable_quantity = @portfolio_investment.quantity.abs
      # It's a sell
      all_investments = @portfolio_investment.aggregate_portfolio_investment.portfolio_investments
      buys = all_investments.allocatable_buys(@portfolio_investment.portfolio_company_id, @portfolio_investment.investment_instrument_id)

      # We need to do the attributions in a transaction
      ActiveRecord::Base.transaction do
        buys.each do |buy|
          Rails.logger.debug { "processing buy #{buy.to_json}" }
          attribution_quantity = [buy.net_quantity, allocatable_quantity].min
          # Create the portfolio attribution
          PortfolioAttribution.create!(entity_id: @portfolio_investment.entity_id, fund_id: @portfolio_investment.fund_id, bought_pi: buy, sold_pi: @portfolio_investment, quantity: -attribution_quantity, investment_date: @portfolio_investment.investment_date)
          # This triggers the computation of net_quantity
          buy.reload

          PortfolioInvestmentUpdate.call(portfolio_investment: buy)

          # Update if we have more to allocate
          allocatable_quantity -= attribution_quantity

          # Check if we are done
          break if allocatable_quantity.zero?
        end
      end
    else
      Rails.logger.debug { "Not allocating #{@portfolio_investment}. Already Allocated" } if @portfolio_investment.portfolio_attributions.count.zero?
      Rails.logger.debug { "Not allocating #{@portfolio_investment} because it's a buy" } if @portfolio_investment.buy?
    end
  end
end
