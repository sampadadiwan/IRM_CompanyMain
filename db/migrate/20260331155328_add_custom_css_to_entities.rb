class AddCustomCssToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :custom_css, :string, limit: 20
  end
end
