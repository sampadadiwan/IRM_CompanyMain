class ChangeAddSetupFeesForCapitalCall < ActiveRecord::Migration[7.0]
  def change
    remove_column :capital_calls, :add_setup_fees
    add_column :capital_calls, :add_fees, :text
  end
end
