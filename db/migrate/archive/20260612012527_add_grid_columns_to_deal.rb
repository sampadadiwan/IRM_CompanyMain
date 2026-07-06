class AddGridColumnsToDeal < ActiveRecord::Migration[8.1]
  def change
    add_column :deals, :grid_columns, :json
  end
end
