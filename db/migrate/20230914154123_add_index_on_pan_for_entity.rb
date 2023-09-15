class AddIndexOnPanForEntity < ActiveRecord::Migration[7.0]
  def change
    add_index :entities, :pan, unique: true, where: 'pan IS NOT NULL'
    add_index :investors, :pan
  end
end
