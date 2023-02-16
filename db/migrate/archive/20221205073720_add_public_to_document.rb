class AddPublicToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :public_visibility, :boolean, default: false
  end
end
