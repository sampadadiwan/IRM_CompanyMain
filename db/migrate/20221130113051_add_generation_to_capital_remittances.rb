class AddGenerationToCapitalRemittances < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_calls, :generate_remittances, :boolean, default: true
    add_column :capital_calls, :generate_remittances_verified, :boolean, default: false
    add_column :capital_distributions, :generate_payments, :boolean, default: true
    add_column :capital_distributions, :generate_payments_paid, :boolean, default: false
  end
end
