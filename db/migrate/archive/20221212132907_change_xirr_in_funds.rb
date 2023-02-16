class ChangeXirrInFunds < ActiveRecord::Migration[7.0]
  def change
    change_column :funds, :rvpi, :decimal, precision: 10, scale: 6, default: 0
    change_column :funds, :dpi, :decimal, precision: 10, scale: 6, default: 0
    change_column :funds, :tvpi, :decimal, precision: 10, scale: 6, default: 0
    change_column :funds, :xirr, :decimal, precision: 10, scale: 6, default: 0
    change_column :funds, :moic, :decimal, precision: 10, scale: 6, default: 0
  end
end
