class AddQuantityAsOfDateToPortfolioInvestment < ActiveRecord::Migration[7.1]
  def change
    add_column :portfolio_investments, :quantity_as_of_date, :decimal, default: 0.0
    add_reference :aggregate_portfolio_investments, :form_type, foreign_key: true
    puts "Updating PortfolioInvestment quantity_as_of_date and AggregatePortfolioInvestment form_type..."
    PortfolioInvestment.all.each do |pi|
      pi.update(quantity_as_of_date: pi.compute_quantity_as_of_date)
    end
    puts "Updating AggregatePortfolioInvestment form_type..."
    AggregatePortfolioInvestment.all.each do |api|
      api.form_type = api.entity.form_types.where(name: "AggregatePortfolioInvestment").last
      api.save
    end
  end
end
