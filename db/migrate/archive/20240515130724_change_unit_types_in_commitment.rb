class ChangeUnitTypesInCommitment < ActiveRecord::Migration[7.1]
  def change
    change_column :capital_commitments, :unit_type, :string, limit: 25
  end
end
