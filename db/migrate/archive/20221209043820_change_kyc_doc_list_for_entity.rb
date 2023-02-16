class ChangeKycDocListForEntity < ActiveRecord::Migration[7.0]
  def change
    change_column :entities, :kyc_doc_list, :string, limit: 100
    change_column :funds, :commitment_doc_list, :string, limit: 100    
  end
end
