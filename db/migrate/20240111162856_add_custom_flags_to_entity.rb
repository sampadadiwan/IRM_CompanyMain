class AddCustomFlagsToEntity < ActiveRecord::Migration[7.1]
  def change
    add_column :entities, :customization_flags, :integer, default: 0
  end
end
