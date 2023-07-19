class AddPanToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :pan, :string, limit: 15
  end
end
