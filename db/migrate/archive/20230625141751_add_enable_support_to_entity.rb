class AddEnableSupportToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :enable_support, :boolean, default: false
  end
end
