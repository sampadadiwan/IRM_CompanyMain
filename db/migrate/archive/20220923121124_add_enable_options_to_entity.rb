class AddEnableOptionsToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :enable_options, :boolean, default: false
    add_column :entities, :enable_captable, :boolean, default: false
  end
end
