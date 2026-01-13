class ChangeUnitsQuantityPrecision < ActiveRecord::Migration[8.0]
  def change
    change_column :capital_commitments,
      :total_fund_units_quantity,
      :decimal,
      precision: 26,
      scale: 8,
      default: 0.0

    change_column :capital_remittances,
      :units_quantity,
      :decimal,
      precision: 26,
      scale: 8,
      default: 0.0

    change_column :capital_distribution_payments,
      :units_quantity,
      :decimal,
      precision: 26,
      scale: 8,
      default: 0.0
  end
end
