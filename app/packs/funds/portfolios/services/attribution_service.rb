class AttributionService
  def initialize(portfolio_investment)
    @portfolio_investment = portfolio_investment
  end

  def setup_attribution
    if @portfolio_investment.sell?
      # Sell quantity is negative
      allocatable_quantity = @portfolio_investment.quantity.abs
      # It's a sell
      all_investments = @portfolio_investment.aggregate_portfolio_investment.portfolio_investments
      buys = all_investments.allocatable_buys(@portfolio_investment.portfolio_company_id, @portfolio_investment.category, @portfolio_investment.sub_category)
      buys = buys.where(capital_commitment_id:) if @portfolio_investment.CoInvest?
      buys = buys.pool if @portfolio_investment.Pool?

      buys.each do |buy|
        Rails.logger.debug { "processing buy #{buy.to_json}" }
        attribution_quantity = [buy.net_quantity, allocatable_quantity].min
        # Create the portfolio attribution
        PortfolioAttribution.create!(entity_id: @portfolio_investment.entity_id, fund_id: @portfolio_investment.fund_id, bought_pi: buy, sold_pi: @portfolio_investment, quantity: -attribution_quantity)
        # This triggers the computation of net_quantity
        buy.reload.save

        # Update if we have more to allocate
        allocatable_quantity -= attribution_quantity

        # Check if we are done
        break if allocatable_quantity.zero?
      end
    end
  end
end
