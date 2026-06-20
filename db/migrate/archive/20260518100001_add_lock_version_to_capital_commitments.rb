class AddLockVersionToCapitalCommitments < ActiveRecord::Migration[7.2]
  def change
    add_column :capital_commitments, :lock_version, :integer, default: 0, null: false
  end
end
