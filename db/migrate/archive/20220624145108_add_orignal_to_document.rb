class AddOrignalToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :orignal, :boolean, default: false
  end
end
