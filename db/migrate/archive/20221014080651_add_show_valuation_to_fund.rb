class AddShowValuationToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :show_valuations, :boolean, default: false
    add_column :funds, :show_fund_ratios, :boolean, default: false
  end
end
