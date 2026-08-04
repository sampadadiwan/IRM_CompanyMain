class StockAdjustmentJob < ApplicationJob
  queue_as :low

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(id)
    Chewy.strategy(:sidekiq) do
      @stock_adjustment = StockAdjustment.find(id)
      @portfolio_company = @stock_adjustment.portfolio_company
      @entity = @portfolio_company.entity

      Rails.logger.info("StockAdjustmentJob: #{@portfolio_company.investor_name} #{@stock_adjustment.investment_instrument} by #{@stock_adjustment.adjustment}")

      ActiveRecord::Base.transaction do
        # A nil adjustment would silently NULL the column via "/ NULL" - the old interpolated
        # SQL raised a syntax error instead, so keep failing loudly for bad data
        raise ArgumentError, "StockAdjustment##{@stock_adjustment.id} has no adjustment value" if @stock_adjustment.adjustment.nil?

        # Parameterized to avoid interpolating the adjustment value into raw SQL
        count = valuations.update_all(["per_share_value_cents = (per_share_value_cents / ?)", @stock_adjustment.adjustment])
        Rails.logger.info("StockAdjustmentJob: Adjusting #{count} valuations")

        Rails.logger.info("StockAdjustmentJob: Adjusting portfolio investments")
        aggregate_portfolio_investments.each do |api|
          api.split(@stock_adjustment.adjustment)
        end
      end
    end
  end

  def aggregate_portfolio_investments
    @entity.aggregate_portfolio_investments.where(portfolio_company_id: @portfolio_company.id, investment_instrument: @stock_adjustment.investment_instrument)
  end

  def valuations
    @portfolio_company.valuations.where(owner: @portfolio_company, investment_instrument: @stock_adjustment.investment_instrument)
  end
end
