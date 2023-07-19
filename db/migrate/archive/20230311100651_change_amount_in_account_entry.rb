class ChangeAmountInAccountEntry < ActiveRecord::Migration[7.0]
  def change
    change_column :account_entries, :amount_cents, :decimal, precision: 30, scale: 8, default: 0
    change_column :account_entries, :folio_amount_cents, :decimal, precision: 30, scale: 8, default: 0
  end
end
