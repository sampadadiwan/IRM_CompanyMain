class AddDeletedAtToAi < ActiveRecord::Migration[7.1]
  def change
    add_column :aggregate_investments, :deleted_at, :datetime
    add_index :aggregate_investments, :deleted_at
  end
end
