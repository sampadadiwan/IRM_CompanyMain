class ChangeValueInFundRatios < ActiveRecord::Migration[7.0]
  def change
    change_column :fund_ratios, :value, :decimal, precision: 20, scale: 8, default: 0
  end
end
