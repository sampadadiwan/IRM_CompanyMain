class AttributionService
  def initialize(portfolio_investment)
    @portfolio_investment = portfolio_investment
  end

  def setup_attribution
    # Allocate only sells, and make sure its not already been allocated
    if @portfolio_investment.sell? && @portfolio_investment.portfolio_attributions.count.zero?
      if @portfolio_investment.fund.portfolio_cost_type == "FIFO"
        Rails.logger.debug { "Allocating #{@portfolio_investment} using FIFO" }
        setup_attribution_fifo
      elsif @portfolio_investment.fund.portfolio_cost_type == "WTD_AVG"
        Rails.logger.debug { "Allocating #{@portfolio_investment} using WTD_AVG" }
        setup_attribution_weighted_avg
      else
        Rails.logger.error { "Unknown portfolio cost type: #{@portfolio_investment.fund.portfolio_cost_type}" }
        raise "Unknown portfolio cost type: #{@portfolio_investment.fund.portfolio_cost_type}"
      end
    else
      Rails.logger.debug { "Not allocating #{@portfolio_investment}. Already Allocated" } if @portfolio_investment.portfolio_attributions.count.zero?
      Rails.logger.debug { "Not allocating #{@portfolio_investment} because it's a buy" } if @portfolio_investment.buy?
    end
  end

  def setup_attribution_fifo
    return unless @portfolio_investment.sell? && @portfolio_investment.portfolio_attributions.count.zero?

    allocatable_quantity = @portfolio_investment.quantity.abs
    all_investments = @portfolio_investment.aggregate_portfolio_investment.portfolio_investments
    buys = all_investments.allocatable_buys(@portfolio_investment.portfolio_company_id, @portfolio_investment.investment_instrument_id)

    ActiveRecord::Base.transaction do
      buys.each do |buy|
        break if allocatable_quantity.zero?

        attribution_quantity = [buy.net_quantity, allocatable_quantity].min

        PortfolioAttribution.create!(
          entity_id: @portfolio_investment.entity_id,
          fund_id: @portfolio_investment.fund_id,
          bought_pi: buy,
          sold_pi: @portfolio_investment,
          quantity: -attribution_quantity,
          investment_date: @portfolio_investment.investment_date
        )

        allocatable_quantity -= attribution_quantity
        buy.reload
        PortfolioInvestmentUpdate.call(portfolio_investment: buy)
      end
    end
  end

  def setup_attribution_weighted_avg
    return unless @portfolio_investment.sell? && @portfolio_investment.portfolio_attributions.count.zero?

    sell_quantity = @portfolio_investment.quantity.abs
    all_investments = @portfolio_investment.aggregate_portfolio_investment.portfolio_investments
    buys = all_investments.allocatable_buys(@portfolio_investment.portfolio_company_id, @portfolio_investment.investment_instrument_id)

    total_buy_quantity = buys.sum(&:net_quantity)
    return if total_buy_quantity.zero?

    ActiveRecord::Base.transaction do
      buys.each do |buy|
        break if sell_quantity.zero?

        proportion = buy.net_quantity.to_f / total_buy_quantity
        attribution_quantity = (sell_quantity * proportion).round(6)
        next if attribution_quantity.zero?

        PortfolioAttribution.create!(
          entity_id: @portfolio_investment.entity_id,
          fund_id: @portfolio_investment.fund_id,
          bought_pi: buy,
          sold_pi: @portfolio_investment,
          quantity: -attribution_quantity,
          investment_date: @portfolio_investment.investment_date
        )

        buy.reload
        PortfolioInvestmentUpdate.call(portfolio_investment: buy)
      end
    end
  end
end
