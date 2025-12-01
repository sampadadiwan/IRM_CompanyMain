class AddWhiteLabelToEntity < ActiveRecord::Migration[8.0]
  def change
    add_column :entities, :white_label, :boolean, default: false
  end
end
