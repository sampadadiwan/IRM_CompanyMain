class AddCumulativeToDistributionFees < ActiveRecord::Migration[8.1]
  def change
    # entry type, cumulative, parent, parent type
    unless column_exists?(:distribution_fees, :cumulative)
      add_column :distribution_fees, :cumulative, :boolean, default: false, null: false
    end
    unless column_exists?(:distribution_fees, :entry_type)
      add_column :distribution_fees, :entry_type, :string
    end
    unless column_exists?(:distribution_fees, :parent_type)
      add_column :distribution_fees, :parent_type, :string
    end
  end
end
