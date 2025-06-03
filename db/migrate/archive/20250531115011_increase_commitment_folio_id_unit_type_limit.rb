class IncreaseCommitmentFolioIdUnitTypeLimit < ActiveRecord::Migration[8.0]
  def change
    # Increase the limit for folio_id and unit_type in commitments table
    change_column :capital_commitments, :folio_id, :string, limit: 40
    change_column :capital_commitments, :unit_type, :string, limit: 40
  end
end
