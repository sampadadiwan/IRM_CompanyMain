class AddGrossAeToCapitalDistributionPayment < ActiveRecord::Migration[7.2]
  def change
    add_column :capital_distribution_payments, :gross_payable_cents, :decimal, precision: 20, scale: 2, default: 0.0    
    add_column :capital_distribution_payments, :gross_of_account_entries_cents, :decimal, precision: 20, scale: 2, default: 0.0
    rename_column :capital_distribution_payments, :fee_cents, :net_of_account_entries_cents    
    rename_column :capital_distribution_payments, :total_amount_cents, :net_payable_cents

    CapitalDistributionPayment.update_all("net_payable_cents = income_with_fees_cents + cost_of_investment_with_fees_cents")

    CapitalDistributionPayment.update_all("gross_payable_cents = net_payable_cents")

  end
end
