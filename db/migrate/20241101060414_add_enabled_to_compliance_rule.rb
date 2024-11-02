class AddEnabledToComplianceRule < ActiveRecord::Migration[7.1]
  def change
    add_column :compliance_rules, :enabled, :boolean, default: true
  end
end
