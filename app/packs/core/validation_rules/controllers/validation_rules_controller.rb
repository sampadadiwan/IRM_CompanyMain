class ValidationRulesController < ApplicationController
  skip_after_action :verify_policy_scoped
  skip_after_action :verify_authorized, only: :evaluate

  # POST /validation_rules/evaluate
  #
  # Params:
  #   target_model  [String]  "Valuation" | "AllocationRun" | "FundRatio" | "FundRatioRunTemplate" | ...
  #   record_id     [Integer] omit or null for new records
  #   attributes    [Hash]    current form field values (unsaved)
  #
  # Returns:
  #   { warnings: [...], blockers: [...] }
  def evaluate
    target_model = params[:target_model].to_s

    unless ValidationRuleEvaluator::CONTEXT_PROVIDERS.key?(target_model)
      return render json: { error: "Unknown target_model: #{target_model}" }, status: :bad_request
    end

    model_class = target_model.constantize

    record = if params[:record_id].present?
               # Scope to the current user's entity so a company_admin from entity A
               # cannot probe records belonging to entity B.
               model_class.find_by(id: params[:record_id], entity_id: current_user.entity_id)
             else
               model_class.new
             end

    return render json: { error: "Record not found" }, status: :not_found if record.nil?

    # permit! is safe here — the record is never persisted, it's only used for evaluation
    raw_attrs = params[:attributes]&.permit!&.to_h&.except(
      "authenticity_token", "controller", "action", "files[]"
    ) || {}

    # Normalise model-specific quirks before assigning
    raw_attrs = normalise_for_evaluation(model_class, raw_attrs)

    record.assign_attributes(raw_attrs.slice(*assignable_attrs(model_class, raw_attrs)))

    Rails.logger.debug { "[RuleEval] #{target_model} attrs after assign: #{debug_attrs(record)}" }

    results  = ValidationRuleEvaluator.call(record:, entity: current_user.entity)
    warnings = results.select(&:warning?)
    blockers = results.select(&:blocker?)

    render json: {
      warnings: serialize(warnings),
      blockers: serialize(blockers)
    }
  end

  private

  # Per-model attribute normalisation before assignment.
  # Handles cases where form field names differ from model attribute names.
  def normalise_for_evaluation(model_class, attrs)
    case model_class.name
    when "Valuation"
      attrs = attrs.dup

      # The multi-create form sends investment_instrument_ids[] (array) but the
      # model has a singular investment_instrument_id — use the first value
      if attrs["investment_instrument_id"].blank? && attrs["investment_instrument_ids[]"].present?
        attrs["investment_instrument_id"] = Array(attrs["investment_instrument_ids[]"]).first
      end

      # monetize needs entity (for currency) before per_share_value can be assigned;
      # fall back to the current user's entity if entity_id is missing from the form
      attrs["entity_id"] ||= current_user.entity_id.to_s

    when "AllocationRun"
      attrs = attrs.dup
      # The allocate form is flat (no model prefix) — entity and fund come from
      # the fund being allocated, not from the form params directly
      attrs["entity_id"] ||= current_user.entity_id.to_s

    when "FundRatio"
      attrs = attrs.dup
      # The generate_fund_ratios form is also flat; supply entity_id for monetize/context
      attrs["entity_id"] ||= current_user.entity_id.to_s

    when "FundRatioRunTemplate"
      attrs = attrs.dup
      # Trigger forms send end_date; the rule engine reads the virtual trigger_end_date attr
      attrs["trigger_end_date"] = attrs.delete("end_date") if attrs.key?("end_date")
      attrs["entity_id"] ||= current_user.entity_id.to_s

    when "CapitalCall"
      attrs = attrs.dup
      # Approval evaluates a persisted record; ensure entity_id is present for scoping
      attrs["entity_id"] ||= current_user.entity_id.to_s

    when "CapitalRemittance"
      attrs = attrs.dup
      # Send-notification evaluates a persisted record; ensure entity_id is present for scoping
      attrs["entity_id"] ||= current_user.entity_id.to_s
    end

    attrs
  end

  # Virtual attr_accessors that are not DB columns but must be assignable for rule evaluation.
  VIRTUAL_ATTRS = {
    "FundRatioRunTemplate" => %w[trigger_end_date]
  }.freeze

  # Build the set of attributes we can safely assign.
  # Includes DB column names, monetize virtual setters, and model-specific virtual attrs.
  def assignable_attrs(model_class, raw_attrs)
    columns      = model_class.column_names
    # monetize creates virtual setters like "per_share_value" alongside "per_share_value_cents";
    # include any incoming key whose cents-column equivalent exists on the model
    virtual_money = raw_attrs.keys.select do |k|
      columns.include?("#{k}_cents")
    end
    virtual = VIRTUAL_ATTRS.fetch(model_class.name, [])
    (columns + virtual_money + virtual).map(&:to_s)
  end

  def serialize(results)
    results.map { |r| { rule_name: r.rule.name, message: r.message, severity: r.severity } }
  end

  # Log the key fields relevant to rule evaluation so mismatches are visible
  def debug_attrs(record)
    cents_cols = record.class.column_names.grep(/_cents$|_date$|^locked$|^value$/)
    raw = record.attributes.slice(*cents_cols)

    # Also log the humanised money accessor (e.g. per_share_value) where it exists —
    # only call it when the record actually responds to the method
    money_vals = record.class.column_names.grep(/_cents$/).each_with_object({}) do |col, h|
      accessor = col.sub("_cents", "")
      h[accessor] = record.public_send(accessor).to_s if record.respond_to?(accessor)
    end

    raw.merge(money_vals)
  end
end
