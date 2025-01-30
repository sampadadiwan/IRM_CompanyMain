class AddFundIdToAccountEntryIndex < ActiveRecord::Migration[7.2]
  def change
    remove_index :account_entries, name: "idx_on_capital_commitment_id_name_entry_type_report_7ae8b000dd"
    add_index :account_entries, [:capital_commitment_id, :fund_id, :name, :entry_type, :reporting_date, :cumulative, :deleted_at], name: "idx_on_capital_commitment_id_fund_id_name_entry_type_report"    
  end
end
