class ChangePanLength < ActiveRecord::Migration[7.1]
  def up
    change_column :investors, :pan, :string, limit: 30
    change_column :entities, :pan, :string, limit: 30
  end
  def down
    # change_column :investors, :pan, :string, limit: 15
    # change_column :entities, :pan, :string, limit: 15
  end
end
