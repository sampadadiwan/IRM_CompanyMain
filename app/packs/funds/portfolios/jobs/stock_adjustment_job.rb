class StockAdjustmentJob < ApplicationJob
  queue_as :low

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(id)
    @stock_adjustment = StockAdjustment.find(id)
    @portfolio_company = @stock_adjustment.portfolio_company
    @entity = @portfolio_company.entity

    Rails.logger.info("StockAdjustmentJob: #{@portfolio_company.investor_name} #{@stock_adjustment.investment_instrument} by #{@stock_adjustment.adjustment}")

    count = valuations.update_all("per_share_value_cents = (per_share_value_cents / #{@stock_adjustment.adjustment})")
    Rails.logger.info("StockAdjustmentJob: Adjusting #{count} valuations")

    Rails.logger.info("StockAdjustmentJob: Adjusting portfolio investments")
    aggregate_portfolio_investments.each do |api|
      api.split(@stock_adjustment.adjustment)
    end
  end

  def aggregate_portfolio_investments
    @entity.aggregate_portfolio_investments.where(portfolio_company_id: @portfolio_company.id, investment_instrument: @stock_adjustment.investment_instrument)
  end

  def valuations
    @portfolio_company.valuations.where(owner: @portfolio_company, investment_instrument: @stock_adjustment.investment_instrument)
  end
end
