class ChangeAccountEntryLength < ActiveRecord::Migration[7.0]
  def change
    change_column :account_entries, :entry_type, :string, length: 50
  end
end
