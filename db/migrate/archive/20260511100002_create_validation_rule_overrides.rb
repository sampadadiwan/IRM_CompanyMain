class CreateValidationRuleOverrides < ActiveRecord::Migration[7.1]
  def change
    create_table :validation_rule_overrides do |t|
      # The global default rule being overridden
      t.references :validation_rule, null: false, foreign_key: true

      # The tenant applying this override
      t.references :entity, null: false, foreign_key: true

      # Set to false to completely disable this rule for the entity
      t.boolean :enabled, null: false, default: true

      # Replaces specific param values from the rule's default params.
      # E.g. { "pct_threshold": 100 } overrides just the threshold, leaving other params alone.
      t.json :param_overrides, null: false

      # Optional custom message that replaces the rule's message_template for this entity
      t.string :message_override

      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.timestamps
    end

    # One override per (rule, entity) pair
    add_index :validation_rule_overrides, %i[validation_rule_id entity_id],
              unique: true,
              name: "idx_validation_rule_overrides_unique"
  end
end
