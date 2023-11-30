class AddRunForToAccountEntry < ActiveRecord::Migration[7.1]
  def change
    add_column :account_entries, :rule_for, :string, limit: 10, default: "Accounting"
  end
end
