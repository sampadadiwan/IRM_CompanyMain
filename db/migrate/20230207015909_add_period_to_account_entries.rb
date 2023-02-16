class AddPeriodToAccountEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :account_entries, :period, :string, limit: 10
  end
end
