class RenameComplianceRuleToComplianceCheck < ActiveRecord::Migration[7.1]
  def change
    rename_table :ai_rules, :ai_rules
    rename_table :compliance_checks, :ai_checks
    rename_column :ai_checks, :compliance_rule_id, :ai_rule_id
  end
end
