class UpdateValuationsNameLimit < ActiveRecord::Migration[8.0]
  def change
    change_column :valuations, :name, :string
  end
end
