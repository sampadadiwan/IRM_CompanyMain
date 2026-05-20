namespace :rules do
  # ── Default rule definitions ────────────────────────────────────────────────
  #
  # Canonical list lives in ValidationRulesDefaults::DEFAULT_RULES.
  # That module is the single source of truth — both this task and the Cucumber
  # seed (features/support/validation_rules_seed.rb) reference it directly.
  #
  # Re-running the task updates condition_tree, params, description, and
  # message_template on existing default rules, but never touches `enabled`
  # state or any ValidationRuleOverride records (tenant customisations are preserved).

  # ── Seed task ────────────────────────────────────────────────────────────────

  desc <<~DESC
    Seed default validation rules for all entities (or a single entity).

    Usage:
      rails rules:seed_defaults              # upserts all global defaults
      rails rules:seed_defaults[123]         # same (entity 123 customises via overrides)

    Idempotent: safe to re-run on every deploy.
    - Creates rules that don't exist yet.
    - Updates condition_tree, params, description, message_template on existing rules.
    - Never changes the `enabled` flag or any ValidationRuleOverride records.
  DESC
  task :seed_defaults, [:entity_id] => :environment do |_, args|
    puts "[rules:seed_defaults] Starting..."
    created = 0
    updated = 0

    ValidationRulesDefaults::DEFAULT_RULES.each do |rule_attrs|
      # Idempotency key: (name, target_model) among global defaults
      rule = ValidationRule.find_or_initialize_by(
        name:         rule_attrs[:name],
        target_model: rule_attrs[:target_model],
        entity_id:    nil,
        is_default:   true
      )

      # These fields are always kept in sync with this file on re-run
      rule.assign_attributes(
        description:      rule_attrs[:description],
        condition_tree:   rule_attrs[:condition_tree],
        params:           rule_attrs[:params],
        message_template: rule_attrs[:message_template],
        severity:         rule_attrs[:severity]
      )

      # Use the enabled flag from the definition if provided; otherwise default off.
      # Rules with enabled: true fire for all entities unless overridden.
      rule.enabled = rule_attrs.fetch(:enabled, false) if rule.new_record?

      if rule.new_record?
        rule.save!
        created += 1
        puts "  [created] #{rule_attrs[:target_model]} / #{rule_attrs[:name]}"
      elsif rule.changed?
        rule.save!
        updated += 1
        puts "  [updated] #{rule_attrs[:target_model]} / #{rule_attrs[:name]} (#{rule.changed.join(', ')})"
      else
        puts "  [ok]      #{rule_attrs[:target_model]} / #{rule_attrs[:name]}"
      end
    end

    puts "[rules:seed_defaults] Done. #{created} created, #{updated} updated."
  end

  # ── Enable / disable all rules for a single entity ───────────────────────────

  desc <<~DESC
    Create or update ValidationRuleOverrides so all global default rules are ENABLED for an entity.

    Usage:
      rails rules:enable_for_entity[123]

    Idempotent: safe to re-run. Creates overrides that don't exist; sets enabled=true on existing ones.
    Run rules:seed_defaults first if the global rules haven't been seeded yet.
  DESC
  task :enable_for_entity, [:entity_id] => :environment do |_, args|
    entity = Entity.find_by(id: args[:entity_id].to_i)
    abort "[rules:enable_for_entity] Entity #{args[:entity_id]} not found." unless entity

    puts "[rules:enable_for_entity] Enabling all rules for entity #{entity.id} (#{entity.name})..."
    created = updated = 0

    ValidationRule.where(is_default: true, entity_id: nil).each do |rule|
      override = ValidationRuleOverride.find_or_initialize_by(validation_rule: rule, entity:)
      new_record = override.new_record?
      override.enabled = true
      override.save!
      new_record ? (created += 1) : (updated += 1)
      puts "  [#{new_record ? 'created' : 'updated'}] #{rule.target_model} / #{rule.name}"
    end

    puts "[rules:enable_for_entity] Done. #{created} created, #{updated} updated."
  end

  desc <<~DESC
    Create or update ValidationRuleOverrides so all global default rules are DISABLED for an entity.

    Usage:
      rails rules:disable_for_entity[123]

    Idempotent: safe to re-run.
  DESC
  task :disable_for_entity, [:entity_id] => :environment do |_, args|
    entity = Entity.find_by(id: args[:entity_id].to_i)
    abort "[rules:disable_for_entity] Entity #{args[:entity_id]} not found." unless entity

    puts "[rules:disable_for_entity] Disabling all rules for entity #{entity.id} (#{entity.name})..."
    created = updated = 0

    ValidationRule.where(is_default: true, entity_id: nil).each do |rule|
      override = ValidationRuleOverride.find_or_initialize_by(validation_rule: rule, entity:)
      new_record = override.new_record?
      override.enabled = false
      override.save!
      new_record ? (created += 1) : (updated += 1)
      puts "  [#{new_record ? 'created' : 'updated'}] #{rule.target_model} / #{rule.name}"
    end

    puts "[rules:disable_for_entity] Done. #{created} created, #{updated} updated."
  end

  # ── Entity override seed task ─────────────────────────────────────────────────

  # Demonstrates override patterns:
  #   1. Tightened threshold   — stricter pct_threshold for valuation swings
  #   2. Custom message        — tenant-branded copy on the allocation-run warning
  #   3. Disabled rule         — entity switches off the fund-ratio quarter-end check
  #   4. Enabled rule          — entity opts in to the run-template quarter-end check
  ENTITY_OVERRIDES = [
    # ── Valuation: tighten the large-increase threshold from 50% → 20% ──────────
    {
      rule_name:       "valuation_large_increase",
      target_model:    "Valuation",
      enabled:         true,
      param_overrides: { "pct_threshold" => 20 },
      message_override: "Per-share value has increased by more than 20% vs. the previous valuation. Please review before confirming."
    },

    # ── Valuation: tighten the large-decrease threshold from 50% → 30% ──────────
    {
      rule_name:       "valuation_large_decrease",
      target_model:    "Valuation",
      enabled:         true,
      param_overrides: { "pct_threshold" => 30 },
      message_override: "Per-share value has decreased by more than 30% vs. the previous valuation. Please review before confirming."
    },

    # ── AllocationRun: keep the rule enabled, add tenant-branded message ─────────
    {
      rule_name:        "allocation_run_date_not_quarter_end",
      target_model:     "AllocationRun",
      enabled:          true,
      param_overrides:  {},
      message_override: "Allocation end date %{end_date} is not a quarter-end. Per our fund admin policy, all runs should close on Mar 31, Jun 30, Sep 30, or Dec 31. Please confirm this is an off-cycle run."
    },

    # ── FundRatio: disable the quarter-end date check entirely ───────────────────
    {
      rule_name:        "fund_ratio_date_not_quarter_end",
      target_model:     "FundRatio",
      enabled:          false,   # entity runs interim ratios monthly — suppress this warning
      param_overrides:  {},
      message_override: nil
    },

    # ── FundRatioRunTemplate: enable the quarter-end trigger date check ──────────
    {
      rule_name:        "fund_ratio_run_template_date_not_quarter_end",
      target_model:     "FundRatioRunTemplate",
      enabled:          true,
      param_overrides:  {},
      message_override: nil
    }
  ].freeze

  desc <<~DESC
    Seed example ValidationRuleOverrides for a specific entity.

    Usage:
      rails rules:seed_entity_overrides[157]   # seeds overrides for entity 157
      rails rules:seed_entity_overrides        # defaults to entity 157

    Idempotent: safe to re-run.
    - Creates overrides that don't exist yet.
    - Updates param_overrides, message_override, and enabled on existing overrides.
  DESC
  task :seed_entity_overrides, [:entity_id] => :environment do |_, args|
    entity_id = (args[:entity_id] || 157).to_i
    entity    = Entity.find_by(id: entity_id)

    unless entity
      puts "[rules:seed_entity_overrides] Entity #{entity_id} not found — aborting."
      exit 1
    end

    puts "[rules:seed_entity_overrides] Seeding overrides for entity #{entity_id} (#{entity.name})..."
    created = 0
    updated = 0

    ENTITY_OVERRIDES.each do |attrs|
      # Look up the global default rule by name + model
      rule = ValidationRule.find_by(
        name:         attrs[:rule_name],
        target_model: attrs[:target_model],
        entity_id:    nil,
        is_default:   true
      )

      unless rule
        puts "  [skip]    #{attrs[:target_model]} / #{attrs[:rule_name]} — global default not found, run rules:seed_defaults first"
        next
      end

      # Idempotency key: one override per (rule, entity) pair
      override = ValidationRuleOverride.find_or_initialize_by(
        validation_rule_id: rule.id,
        entity_id:          entity_id
      )

      override.assign_attributes(
        enabled:          attrs[:enabled],
        param_overrides:  attrs[:param_overrides],
        message_override: attrs[:message_override]
      )

      if override.new_record?
        override.save!
        created += 1
        action = attrs[:enabled] ? "enabled=true" : "DISABLED"
        puts "  [created] #{attrs[:target_model]} / #{attrs[:rule_name]} (#{action}, params=#{attrs[:param_overrides]})"
      elsif override.changed?
        override.save!
        updated += 1
        puts "  [updated] #{attrs[:target_model]} / #{attrs[:rule_name]} (#{override.changed.join(', ')})"
      else
        puts "  [ok]      #{attrs[:target_model]} / #{attrs[:rule_name]}"
      end
    end

    puts "[rules:seed_entity_overrides] Done. #{created} created, #{updated} updated."
  end
end
