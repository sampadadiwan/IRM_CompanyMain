class StockSplitter
  def initialize(portfolio_investment)
    @portfolio_investment = portfolio_investment
  end

  def split(stock_split_ratio)
    Rails.logger.info("StockSplitter: #{@portfolio_investment} split by #{stock_split_ratio}")
    # Update the attributions first as they influence the sold & net quantity
    @portfolio_investment.portfolio_attributions.each do |pa|
      Rails.logger.info("StockSplitter: Updating attribution #{pa} orig_quantity: #{pa.quantity} new_quantity: #{pa.quantity * stock_split_ratio}")
      pa.quantity *= stock_split_ratio
      pa.save
    end

    @portfolio_investment.portfolio_attributions.reload
    @portfolio_investment.reload

    # Update the quantity and cost
    Rails.logger.info("StockSplitter: Updating portfolio investment #{@portfolio_investment} orig_quantity: #{@portfolio_investment.quantity} new_quantity: #{@portfolio_investment.quantity * stock_split_ratio}")
    @portfolio_investment.quantity *= stock_split_ratio
    # self.sold_quantity *= stock_split_ratio
    # self.net_quantity *= stock_split_ratio
    @portfolio_investment.notes ||= ""
    @portfolio_investment.notes += "Stock adjusted by factor #{stock_split_ratio} on #{Time.zone.today.strftime('%d %b %Y')}.\n"
    result = PortfolioInvestmentUpdate.call(portfolio_investment: @portfolio_investment)
    raise "StockSplitter: PortfolioInvestmentUpdate failed: #{result[:errors]}" unless result.success?
  end
end
