class AddInvestmentAmountToCapitalRemittance < ActiveRecord::Migration[8.0]
  def change
    add_column :capital_remittances, :investment_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :capital_remittances, :folio_investment_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
  end
end
