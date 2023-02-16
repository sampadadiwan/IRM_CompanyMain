class AddGeneratedFlagToAccountEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :account_entries, :generated, :boolean, default: false
  end
end
