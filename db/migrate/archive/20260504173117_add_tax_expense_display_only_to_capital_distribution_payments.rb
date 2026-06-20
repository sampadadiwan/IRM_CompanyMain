class AddTaxExpenseDisplayOnlyToCapitalDistributionPayments < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:capital_distribution_payments, :tax_with_fees_cents)
      add_column :capital_distribution_payments, :tax_with_fees_cents, :decimal, precision: 20, scale: 2, default: 0
    end
    unless column_exists?(:capital_distribution_payments, :expense_with_fees_cents)
      add_column :capital_distribution_payments, :expense_with_fees_cents, :decimal, precision: 20, scale: 2, default: 0
    end
    unless column_exists?(:capital_distribution_payments, :display_only_with_fees_cents)
      add_column :capital_distribution_payments, :display_only_with_fees_cents, :decimal, precision: 20, scale: 2, default: 0
    end
  end
end
