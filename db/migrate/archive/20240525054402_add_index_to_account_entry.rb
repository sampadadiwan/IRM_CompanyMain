class AddIndexToAccountEntry < ActiveRecord::Migration[7.1]
  def change
    add_index :account_entries, :entry_type
    add_index :account_entries, :name
    add_index :account_entries, :reporting_date
    add_index :portfolio_investments, :investment_date
    add_index :stock_conversions, :conversion_date
    add_index :valuations, :valuation_date
    # Really delete account entries which are not needed.
    puts "Deleting account entries which are not needed."
    AccountEntry.with_deleted.where.not(deleted_at: nil).delete_all
  end
end
