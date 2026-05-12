class ChangeValidationRulesEnabledDefault < ActiveRecord::Migration[8.1]
  def change
    # Rules are off by default; entities opt in via ValidationRuleOverride with enabled=true.
    # This aligns the DB default with the seed task which now creates rules with enabled=false.
    change_column_default :validation_rules, :enabled, from: true, to: false
  end
end
