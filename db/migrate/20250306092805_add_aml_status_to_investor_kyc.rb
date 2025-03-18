class AddAmlStatusToInvestorKyc < ActiveRecord::Migration[7.2]
  def change
    unless column_exists?(:investor_kycs, :aml_status)
      add_column :investor_kycs, :aml_status, :string
    end
  end
end
