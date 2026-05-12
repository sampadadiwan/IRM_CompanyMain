# Provides rule seeding for Cucumber tests without shelling out to rake.
# DEFAULT_RULES is sourced from ValidationRulesDefaults — the single source
# of truth shared with lib/tasks/validation_rules.rake.
module ValidationRulesSeed
  def self.seed!
    ValidationRulesDefaults::DEFAULT_RULES.each do |attrs|
      rule = ValidationRule.find_or_initialize_by(
        name:         attrs[:name],
        target_model: attrs[:target_model],
        entity_id:    nil,
        is_default:   true
      )
      rule.assign_attributes(
        description:      attrs[:description],
        condition_tree:   attrs[:condition_tree],
        params:           attrs[:params],
        message_template: attrs[:message_template],
        severity:         attrs[:severity]
      )
      # Default off — entities opt in via ValidationRuleOverride with enabled=true
      rule.enabled = false if rule.new_record?
      rule.save!
    end
  end

  # Creates (or updates) a ValidationRuleOverride with enabled=true for every global
  # default rule, for the given entity.  Call this in scenarios where the entity
  # has opted in to the validation rule engine.
  def self.enable_for_entity!(entity)
    ValidationRule.where(is_default: true, entity_id: nil).each do |rule|
      override = ValidationRuleOverride.find_or_initialize_by(
        validation_rule: rule,
        entity:          entity
      )
      override.enabled = true
      override.save!
    end
  end

  # Creates (or updates) a ValidationRuleOverride with enabled=false for every global
  # default rule, for the given entity.  Call this in scenarios where the entity
  # has explicitly opted out (suppresses all rule firing regardless of global defaults).
  def self.disable_for_entity!(entity)
    ValidationRule.where(is_default: true, entity_id: nil).each do |rule|
      override = ValidationRuleOverride.find_or_initialize_by(
        validation_rule: rule,
        entity:          entity
      )
      override.enabled = false
      override.save!
    end
  end
end
