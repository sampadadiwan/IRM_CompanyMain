class AddFormTypeToCapitalRemittancePayment < ActiveRecord::Migration[7.2]
  def change
    add_reference :capital_remittance_payments, :form_type, null: true, foreign_key: true
  end
end
