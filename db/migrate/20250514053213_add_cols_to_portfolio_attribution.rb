class AddColsToPortfolioAttribution < ActiveRecord::Migration[8.0]
  def change
    add_column :portfolio_attributions, :sale_amount_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :portfolio_attributions, :gain_cents, :decimal, precision: 20, scale: 2, default: 0

    add_column :aggregate_portfolio_investments, :ex_expenses_amount_cents, :decimal, precision: 20, scale: 2, default: 0

    # We need to recomputation the amounts for all PortfolioAttributions 
    puts "Recomputing amounts for all PortfolioAttributions"
    PortfolioAttribution.all.each do |pa|
      pa.compute_amounts
      pa.save(validate: false)
    end
    puts "Recomputing amounts for all PortfolioAttributions done"
  end
end
