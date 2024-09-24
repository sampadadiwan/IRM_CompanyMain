class AddDateIndexToCapitalRemittancePayment < ActiveRecord::Migration[7.1]
  def change
    add_index :capital_remittance_payments, :payment_date
    add_index :capital_remittances, :remittance_date
    add_index :capital_commitments, :commitment_date
    add_index :portfolio_cashflows, :payment_date    
  end
end
