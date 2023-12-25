class ChangePerShareInValuations < ActiveRecord::Migration[7.0]
  def change
    change_column :valuations, :per_share_value_cents, :decimal, precision: 20, scale: 8, default: 0.0
  end
end
