class AddAccountEntryIndexForCommitmentNameReportingDate < ActiveRecord::Migration[8.0]
  def change
    add_index :account_entries, [:capital_commitment_id, :name, :reporting_date], name: :idx_ae_cc_name_date
  end
end
