class AddEsignToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :esign_required, :boolean, default: false
    add_column :capital_commitments, :esign_completed, :boolean, default: false
    add_column :capital_commitments, :esign_provider, :string, limit: 10
    add_column :capital_commitments, :esign_link, :string
  end
end
