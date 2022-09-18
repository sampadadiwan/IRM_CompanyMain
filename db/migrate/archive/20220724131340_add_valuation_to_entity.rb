class AddValuationToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :per_share_value_cents, :decimal, precision: 15, scale: 2, default: "0.0"
  end
end
