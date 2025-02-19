class AddExCostToPortfolioInvestment < ActiveRecord::Migration[7.2]
  def change
    add_column :portfolio_investments, :ex_expenses_amount_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :portfolio_investments, :ex_expenses_base_amount_cents, :decimal, precision: 20, scale: 2, default: 0

    # Update existing data
    PortfolioInvestment.update_all("ex_expenses_amount_cents = amount_cents, ex_expenses_base_amount_cents = base_amount_cents")
  end
end
