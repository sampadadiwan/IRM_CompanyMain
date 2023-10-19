class AddRemittanceDateToCapitalRemittance < ActiveRecord::Migration[7.1]
  def change
    add_column :capital_remittances, :remittance_date, :date
    CapitalRemittance.joins(:capital_call).update_all("capital_remittances.remittance_date=capital_calls.due_date")
  end
end
