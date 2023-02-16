class AddExplainationToAccountEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :account_entries, :explanation, :text
  end
end
