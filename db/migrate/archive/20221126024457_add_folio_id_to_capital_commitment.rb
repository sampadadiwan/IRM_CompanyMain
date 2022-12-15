class AddFolioIdToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :folio_id, :string, limit: 20
  end
end
