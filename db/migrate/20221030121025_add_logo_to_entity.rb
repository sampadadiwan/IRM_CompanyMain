class AddLogoToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :logo_data, :text
  end
end
