class ChangeRemittancePaymentsInvestorIdNull < ActiveRecord::Migration[8.0]
  def change
    change_column_null :capital_remittance_payments, :investor_id, true
  end
end
