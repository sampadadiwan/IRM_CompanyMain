class RemoveFundRatioValueOutOfRangeRule < ActiveRecord::Migration[7.2]
  def up
    rule = ValidationRule.find_by(name: "fund_ratio_value_out_of_range", entity_id: nil, is_default: true)
    return unless rule

    # Delete entity overrides first (no cascade on the FK).
    ValidationRuleOverride.where(validation_rule: rule).delete_all
    rule.delete
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
