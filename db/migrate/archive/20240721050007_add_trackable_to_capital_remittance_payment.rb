class AddTrackableToCapitalRemittancePayment < ActiveRecord::Migration[7.1]
  def change
    add_column :capital_remittance_payments, :deleted_at, :datetime
    add_index :capital_remittance_payments, :deleted_at
  end
end
