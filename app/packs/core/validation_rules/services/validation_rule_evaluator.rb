# Orchestrates rule evaluation for a record being saved.
#
# Resolution order:
#   1. Global default rules (entity_id IS NULL) — load overrides for this entity
#      a. Skip if override.enabled == false
#      b. Merge param_overrides on top of the rule's default params
#   2. Entity-specific custom rules (entity_id = current entity) — no override needed
#
# Returns an array of Result structs for every rule that fired.
class ValidationRuleEvaluator
  # Registry mapping target_model strings to their ContextProvider classes.
  # Add new models here when extending the engine.
  CONTEXT_PROVIDERS = {
    "Valuation" => ValuationRuleContextProvider,
    "AllocationRun" => AllocationRunRuleContextProvider,
    "FundRatio" => FundRatioRuleContextProvider,
    "FundRatioRunTemplate" => FundRatioRunTemplateRuleContextProvider,
    "CapitalCall" => CapitalCallRuleContextProvider,
    "CapitalRemittance" => CapitalRemittanceRuleContextProvider
  }.freeze

  # What the caller gets back for each fired rule
  Result = Struct.new(:rule, :severity, :message, keyword_init: true) do
    def warning? = severity == "warning"
    def blocker? = severity == "blocker"
  end

  # ── Public interface ─────────────────────────────────────────────────────────

  # @param record [AR]     The record being saved (unsaved changes already assigned)
  # @param entity [Entity] The tenant context
  # @return [Array<Result>]
  def self.call(record:, entity:)
    new(record:, entity:).call
  end

  def initialize(record:, entity:)
    @record       = record
    @entity       = entity
    @target_model = record.class.name
  end

  def call
    active_rules = resolve_active_rules # [[ValidationRule, ValidationRuleOverride|nil], ...]

    Rails.logger.debug { "[RuleEval] #{active_rules.size} active rule(s) for #{@target_model}" }

    active_rules.filter_map do |rule, override|
      # Context is built per-rule so the provider receives that rule's resolved params
      # (e.g. n_days differs between allocation_run_valuation_exists and allocation_run_fx_rates_exist)
      params    = resolve_params(rule, override)
      context   = build_context(params)
      triggered = ConditionTreeEvaluator.call(
        tree: rule.condition_tree,
        record: @record,
        context:,
        params:
      )

      Rails.logger.debug { "[RuleEval] #{rule.name}: params=#{params.inspect} context=#{context.inspect} triggered=#{triggered}" }

      next unless triggered

      message  = override&.resolved_message.presence || rule.message_template
      # severity_override lets a tenant escalate a warning → blocker or downgrade a blocker → warning
      severity = override&.resolved_severity || rule.severity
      Result.new(rule:, severity:, message: interpolate(message, params, context))
    end
  end

  private

  # ── Context building ─────────────────────────────────────────────────────────

  # Calls the model-specific ContextProvider to build the named value hash.
  # params are forwarded so providers can perform parameterized DB queries
  # (e.g. AllocationRunRuleContextProvider uses n_days to scope date windows).
  #
  # Results are memoized per params hash so rules that share identical params
  # (e.g. all Valuation rules use {}) only trigger one DB round-trip.
  def build_context(params = {})
    @context_cache ||= {}
    @context_cache[params] ||= compute_context(params)
  end

  def compute_context(params)
    provider_class = CONTEXT_PROVIDERS[@target_model]
    return {} unless provider_class

    provider_class.new.call(record: @record, entity: @entity, params:)
  rescue StandardError => e
    # A broken context provider must not block saves — log and continue with empty context
    Rails.logger.error("[ValidationRuleEvaluator] Context provider error for #{@target_model}: #{e.message}")
    {}
  end

  # ── Rule resolution ──────────────────────────────────────────────────────────

  # Returns pairs of [rule, override_or_nil] for every rule that should be evaluated
  def resolve_active_rules
    results = []

    # --- Global defaults (entity_id IS NULL) ---
    # Load ALL global rules regardless of their enabled flag — the effective state
    # is determined below: if no override exists the rule's own enabled flag decides.
    # Rules with enabled=true fire for all entities; entities opt out via an override with enabled=false.
    global_rules = ValidationRule
                   .global_defaults
                   .for_model(@target_model)

    # Fetch all overrides for this entity in one query, keyed by validation_rule_id
    overrides_by_rule_id = ValidationRuleOverride
                           .where(entity: @entity, validation_rule: global_rules)
                           .includes(:validation_rule) # avoids N+1 when override.resolved_message accesses validation_rule.message_template
                           .index_by(&:validation_rule_id)

    global_rules.each do |rule|
      override = overrides_by_rule_id[rule.id]

      # Override wins when present; fall back to the rule's own enabled flag.
      # Globally-enabled rules (enabled=true) fire for all entities unless overridden to disabled.
      effective_enabled = override ? override.enabled : rule.enabled
      next unless effective_enabled

      results << [rule, override]
    end

    # --- Entity-specific custom rules ---
    # These are never global defaults; no override record is needed
    ValidationRule
      .for_entity(@entity.id)
      .for_model(@target_model)
      .enabled
      .each { |rule| results << [rule, nil] }

    results
  end

  # ── Param resolution ─────────────────────────────────────────────────────────

  # Merge the entity's param overrides on top of the rule's default params.
  # Result is what ConditionTreeEvaluator receives as its `params` argument.
  def resolve_params(rule, override)
    rule.params.merge(override&.param_overrides || {})
  end

  # ── Message interpolation ─────────────────────────────────────────────────────

  # Substitute %{name} placeholders with record attributes, context values, and resolved params.
  # Priority (highest → lowest): record attributes > context values > params.
  # Falls back to raw template on any substitution error.
  def interpolate(template, params, context = {})
    bindings = params.symbolize_keys
                     .merge(context.transform_keys { |k| k.to_s.to_sym })
                     .merge(@record.attributes.symbolize_keys)
    template % bindings
  rescue KeyError, ArgumentError
    template
  end
end
