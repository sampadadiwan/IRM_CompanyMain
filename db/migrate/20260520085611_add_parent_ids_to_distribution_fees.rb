class AddParentIdsToDistributionFees < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:distribution_fees, :parent_ids)
      add_column :distribution_fees, :parent_ids, :string
    end
    if column_exists?(:distribution_fees, :parent_id)
      remove_column :distribution_fees, :parent_id
    end
  end
end
