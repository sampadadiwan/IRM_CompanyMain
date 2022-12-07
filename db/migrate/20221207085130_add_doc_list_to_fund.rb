class AddDocListToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :commitment_doc_list, :string, limit: 30
    add_column :entities, :kyc_doc_list, :string, limit: 30
    add_reference :esigns, :document, null: true, foreign_key: true
  end
end
