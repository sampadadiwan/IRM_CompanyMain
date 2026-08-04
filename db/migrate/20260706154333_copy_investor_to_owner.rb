class CopyInvestorToOwner < ActiveRecord::Migration[8.1]
  def change
    # 1. Update the column default for future rows
    change_column_default :notes, :owner_type, from: nil, to: "Investor"

    # 2. Copy data and backfill the default value using raw SQL
    up_only do
      execute <<-SQL
        UPDATE notes
        SET owner_id = investor_id,
            owner_type = COALESCE(owner_type, 'Investor')
      SQL
    end
  end
end
