class AddRefNoToCapitalRemittancePayment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_remittance_payments, :reference_no, :string, limit: 40
  end
end
