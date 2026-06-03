class AddAuditNameToDistributionFees < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:distribution_fees, :audit_name)
      add_column :distribution_fees, :audit_name, :string, limit: 65 # same as name column
    end
  end
end
