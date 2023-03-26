class AddFeederToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :feeder_fund, :boolean, default: false
    change_column :funds, :unit_types, :string, limit: 100
  end
end
