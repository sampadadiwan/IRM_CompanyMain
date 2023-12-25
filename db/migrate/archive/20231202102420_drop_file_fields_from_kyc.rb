class DropFileFieldsFromKyc < ActiveRecord::Migration[7.1]
  def change
    remove_column :investor_kycs, :address_proof_data
    remove_column :investor_kycs, :cheque_data
  end
end
