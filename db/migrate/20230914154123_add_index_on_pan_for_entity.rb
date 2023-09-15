class AddIndexOnPanForEntity < ActiveRecord::Migration[7.0]
  def change
    add_index :entities, :pan
    add_index :investors, :pan
  end
end
