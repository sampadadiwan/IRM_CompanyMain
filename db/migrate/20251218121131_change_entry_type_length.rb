class ChangeEntryTypeLength < ActiveRecord::Migration[8.0]
  def change
    change_column :account_entries, :entry_type, :string, limit: 60
    change_column :fund_formulas, :entry_type, :string, limit: 60
  end
end
