class AddPaymentDateToCapitalRemmittance < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_remittances, :payment_date, :date
  end
end
