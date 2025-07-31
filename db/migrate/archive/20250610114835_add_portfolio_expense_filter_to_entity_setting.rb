class AddPortfolioExpenseFilterToEntitySetting < ActiveRecord::Migration[8.0]
  def change
    add_column :entity_settings, :portflio_expense_account_entry_filter, :string
  end
end
