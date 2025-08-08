class AddProformaToPortfolioInvestment < ActiveRecord::Migration[8.0]
  def change
    add_column :portfolio_investments, :proforma, :boolean, default: false, null: false
  end
end
