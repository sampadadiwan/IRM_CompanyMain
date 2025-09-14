class AddNameIndexToAccountEntry < ActiveRecord::Migration[8.0]
  def change
    # add_index for fund_id, name, reporting_date
    add_index :account_entries, [:fund_id, :name, :reporting_date], name: 'idx_fund_id_and_name_and_reporting_date'
    # add_index for fund_id, entry_type, reporting_date
    add_index :account_entries, [:fund_id, :entry_type, :reporting_date], name: 'idx_fund_id_and_entry_type_and_reporting_date'
  end
end
