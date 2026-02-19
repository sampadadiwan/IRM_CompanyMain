class ChangePercentageChangePrecision < ActiveRecord::Migration[8.1]
  def change
    change_column :kpis,
      :percentage_change,
      :decimal,
      precision: 6,
      scale: 2,
      default: 0.0
  end
end
