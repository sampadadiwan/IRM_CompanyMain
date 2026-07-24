class AddManualOverrideToInvestorKycs < ActiveRecord::Migration[8.1]
  def change
    add_column :investor_kycs, :aml_manual_override, :boolean, default: false, null: false unless column_exists?(:investor_kycs, :aml_manual_override)
    add_column :investor_kycs, :aml_override_reason, :text unless column_exists?(:investor_kycs, :aml_override_reason)
  end
end
