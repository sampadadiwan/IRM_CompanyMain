class RenameAmountToIncomeForRemittancePayments < ActiveRecord::Migration[7.2]
  def change
    rename_column :capital_distribution_payments, :amount_cents, :income_cents
    CapitalDistributionPayment.update_all("income_cents = income_cents - cost_of_investment_cents")
  end
end
