class AddParanoiaToValuation < ActiveRecord::Migration[7.0]
  def change
    add_column :valuations, :deleted_at, :datetime
    add_index :valuations, :deleted_at
  end
end
