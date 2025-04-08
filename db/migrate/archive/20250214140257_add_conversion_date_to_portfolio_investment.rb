class AddConversionDateToPortfolioInvestment < ActiveRecord::Migration[7.2]
  def change
    add_column :portfolio_investments, :conversion_date, :date
    add_index :portfolio_investments, :conversion_date

    StockConversion.all.each do |sc|
      sc.to_portfolio_investment&.update_columns(conversion_date: sc.conversion_date)
    end
  end
end
