class StockSplitter

    def initialize(portfolio_investment)
        @portfolio_investment = portfolio_investment
    end

    def split(stock_split_ratio)
        # Update the attributions first as they influence the sold & net quantity
        @portfolio_investment.portfolio_attributions.each do |pa|
          pa.quantity *= stock_split_ratio
          pa.save
        end
    
        @portfolio_investment.portfolio_attributions.reload
        @portfolio_investment.reload
    
        # Update the quantity and cost
        @portfolio_investment.quantity *= stock_split_ratio
        # self.sold_quantity *= stock_split_ratio
        # self.net_quantity *= stock_split_ratio
        @portfolio_investment.notes ||= ""
        @portfolio_investment.notes += "Stock split #{stock_split_ratio} on #{Time.zone.today}\n"
        @portfolio_investment.save
    end
end