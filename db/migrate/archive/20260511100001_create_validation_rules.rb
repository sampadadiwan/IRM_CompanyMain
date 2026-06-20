class CreateValidationRules < ActiveRecord::Migration[7.1]
  def change
    create_table :validation_rules do |t|
      # entity_id is NULL for global default rules (available to all tenants).
      # When set, the rule is private to that entity only.
      t.references :entity, null: true, foreign_key: true

      # Which model this rule applies to: "Valuation", "AllocationRun", "FundRatio"
      t.string :target_model, null: false

      # Human-readable rule name; unique within (entity, model) scope
      t.string :name, null: false

      # Shown in the admin UI to explain what the rule checks
      t.text :description

      # JSON condition tree evaluated against the record + context.
      # Structure: { "op": "AND"|"OR", "conditions": [...] }
      # Leaf nodes: { "field": "...", "op": "...", "param": "...", "compare_to": "context.key" }
      t.json :condition_tree, null: false

      # Named parameter defaults referenced by the condition_tree.
      # E.g. { "pct_threshold": 50 }
      # Overridden per-entity via validation_rule_overrides.param_overrides.
      t.json :params, null: false

      # "warning" = user must confirm before saving.
      # "blocker" = user cannot save until the condition is resolved.
      t.string :severity, null: false, default: "warning"

      # Message shown to the user. Supports %{field_name} interpolation from the record.
      t.string :message_template, null: false

      # Soft-disable at the rule level; entity can also disable via override.
      t.boolean :enabled, null: false, default: true

      # True when created by the rake seed task; prevents accidental duplication.
      t.boolean :is_default, null: false, default: false

      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.timestamps
    end

    # Unique name per (entity, model) — NULL entity_id counts as distinct in MySQL,
    # so global defaults (entity_id NULL) won't collide with entity-specific rules.
    add_index :validation_rules, %i[name target_model entity_id],
              unique: true,
              name: "idx_validation_rules_unique_name"

    add_index :validation_rules, :target_model
  end
end
