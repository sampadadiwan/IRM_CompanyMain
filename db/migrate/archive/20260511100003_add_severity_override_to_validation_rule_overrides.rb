class AddSeverityOverrideToValidationRuleOverrides < ActiveRecord::Migration[7.1]
  def change
    # NULL means "inherit severity from the parent ValidationRule"
    add_column :validation_rule_overrides, :severity_override, :string, null: true, default: nil
  end
end
