class AddFilesToInvestorKyc < ActiveRecord::Migration[7.1]
  def change
    remove_column :investor_kycs, :video_data
    add_column :investor_kycs, :address_proof_data, :text
    add_column :investor_kycs, :cheque_data, :text    
  end
end
