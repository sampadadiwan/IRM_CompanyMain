class ChangeAmoutnCentsInAccountEntry < ActiveRecord::Migration[7.0]
  def change
    change_column :account_entries, :amount_cents, :decimal, precision: 25, scale: 2, default: "0.0"
  end
end
