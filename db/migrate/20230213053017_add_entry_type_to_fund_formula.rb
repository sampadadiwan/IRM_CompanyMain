class AddEntryTypeToFundFormula < ActiveRecord::Migration[7.0]
  def change
    add_column :fund_formulas, :entry_type, :string, limit: 50
    change_column :account_entries, :entry_type, :string, limit: 50
  end
end
