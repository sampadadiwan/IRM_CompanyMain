class AddShowFundUnitsToFund < ActiveRecord::Migration[7.1]
  def change
    add_column :funds, :show_fund_units, :boolean, default: false
  end
end
