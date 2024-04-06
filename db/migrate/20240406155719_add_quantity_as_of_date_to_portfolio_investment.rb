class AddQuantityAsOfDateToPortfolioInvestment < ActiveRecord::Migration[7.1]
  def change
    add_column :portfolio_investments, :quantity_as_of_date, :decimal, default: 0.0
    PortfolioInvestment.all.each do |pi|
      pi.update(quantity_as_of_date: pi.compute_quantity_as_of_date)
    end
  end
end
