class AddFundRatiosToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :rvpi, :decimal, precision: 9, scale: 6, default: 0
    add_column :funds, :dpi, :decimal, precision: 9, scale: 6, default: 0
    add_column :funds, :tvpi, :decimal, precision: 9, scale: 6, default: 0
    add_column :funds, :xirr, :decimal, precision: 9, scale: 6, default: 0
    add_column :funds, :moic, :decimal, precision: 9, scale: 6, default: 0
  end
end
