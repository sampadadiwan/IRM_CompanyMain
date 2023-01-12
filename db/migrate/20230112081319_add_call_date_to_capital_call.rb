class AddCallDateToCapitalCall < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_calls, :call_date, :date
    CapitalCall.update_all("call_date=created_at")
  end
end
