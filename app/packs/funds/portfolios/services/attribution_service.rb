class AttributionService
  def initialize(portfolio_investment)
    @portfolio_investment = portfolio_investment
  end

  def setup_attribution
    # Allocate only sells, and make sure its not already been allocated
    if @portfolio_investment.sell? && @portfolio_investment.portfolio_attributions.none?
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
      Rails.logger.debug { "Not allocating #{@portfolio_investment}. Already Allocated" } if @portfolio_investment.portfolio_attributions.none?
      Rails.logger.debug { "Not allocating #{@portfolio_investment} because it's a buy" } if @portfolio_investment.buy?
    end
  end

  def setup_attribution_fifo
    return unless @portfolio_investment.sell? && @portfolio_investment.portfolio_attributions.none?

    allocatable_quantity = @portfolio_investment.quantity.abs
    all_investments = @portfolio_investment.aggregate_portfolio_investment.portfolio_investments
    buys = all_investments.allocatable_buys(@portfolio_investment.portfolio_company_id, @portfolio_investment.investment_instrument_id)

    ActiveRecord::Base.transaction do
      buys.each do |buy|
        break if allocatable_quantity.zero?

        # Row-lock the buy before reading net_quantity. Without this, two sells created
        # close together (e.g. the duplicate-PI scenario this whole feature is about) each
        # start this loop from their own unlocked read of `buys`, so both can see the same
        # pre-consumption net_quantity and over-allocate against the same lot. FOR UPDATE
        # serializes concurrent jobs on this row; on SQLite (test env) it's a harmless no-op
        # since SQLite has no row-level locking.
        buy.lock!
        next if buy.net_quantity <= 0

        attribution_quantity = [buy.net_quantity, allocatable_quantity].min
        next if attribution_quantity.zero?

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
    return unless @portfolio_investment.sell? && @portfolio_investment.portfolio_attributions.none?

    sell_quantity = @portfolio_investment.quantity.abs
    all_investments = @portfolio_investment.aggregate_portfolio_investment.portfolio_investments
    buys = all_investments.allocatable_buys(@portfolio_investment.portfolio_company_id, @portfolio_investment.investment_instrument_id)

    ActiveRecord::Base.transaction do
      # Lock every eligible buy up front, in the same investment_date order the scope
      # already sorts by (so two concurrent sells always acquire locks in that same order
      # and can't deadlock each other). Without this, two duplicate sells created close
      # together would each compute proportions off the same pre-consumption net_quantity
      # snapshot and over-allocate the same lots — same underlying race as the FIFO path.
      buys = buys.to_a.each(&:lock!)
      total_buy_quantity = buys.sum(&:net_quantity)
      next if total_buy_quantity.zero?

      buys.each do |buy|
        break if sell_quantity.zero?

        proportion = buy.net_quantity.to_f / total_buy_quantity
        # Capped at buy.net_quantity as a safety net: proportions are computed from the
        # now-locked, up-to-date net_quantity values, but rounding could otherwise still
        # nudge a single buy's share a hair past what's actually left in that lot.
        attribution_quantity = [(sell_quantity * proportion).round(6), buy.net_quantity].min
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
