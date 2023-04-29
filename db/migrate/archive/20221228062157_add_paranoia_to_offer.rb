class AddParanoiaToOffer < ActiveRecord::Migration[7.0]
  def change
    add_column :offers, :deleted_at, :datetime
    add_index :offers, :deleted_at
    add_column :interests, :deleted_at, :datetime
    add_index :interests, :deleted_at
  end
end
