# Walks a condition_tree JSON structure and evaluates it against a record + context.
#
# condition_tree shape:
#   Composite node: { "op": "AND"|"OR", "conditions": [ ...nodes ] }
#   Leaf node:      { "field": "valuation_date", "op": "not_quarter_end" }
#                   { "field": "valuation_cents", "op": "pct_change_gt",
#                     "param": "pct_threshold", "compare_to": "context.prev_valuation_cents" }
#
# Fields prefixed with "context." are resolved from the ContextProvider hash.
# All other field names are resolved directly from the record's attributes.
#
# Returns true when the condition is violated (i.e. the rule should fire).
class ConditionTreeEvaluator
  # Quarter-end months: last day of Mar / Jun / Sep / Dec
  QUARTER_END_MONTHS = [3, 6, 9, 12].freeze

  # ── Public interface ─────────────────────────────────────────────────────────

  # @param tree    [Hash]   Parsed condition_tree from the database
  # @param record  [AR]     The ActiveRecord instance being validated (unsaved changes applied)
  # @param context [Hash]   Named values from the model's ContextProvider (symbol keys)
  # @param params  [Hash]   Resolved param values (rule defaults merged with entity overrides)
  # @return        [Boolean] true = rule fires (condition violated)
  def self.call(tree:, record:, context:, params:)
    new(tree:, record:, context:, params:).call
  end

  def initialize(tree:, record:, context:, params:)
    @tree    = tree
    @record  = record
    @context = context.transform_keys(&:to_s) # normalise to string keys
    @params  = params.transform_keys(&:to_s)
  end

  def call
    evaluate_node(@tree)
  end

  private

  # ── Node dispatch ────────────────────────────────────────────────────────────

  def evaluate_node(node)
    case node["op"]
    when "AND" then node["conditions"].all? { |c| evaluate_node(c) }
    when "OR"  then node["conditions"].any? { |c| evaluate_node(c) }
    else             evaluate_leaf(node)
    end
  end

  # ── Leaf operators ───────────────────────────────────────────────────────────

  def evaluate_leaf(node)
    op = node["op"]
    case op
    when "not_quarter_end"  then evaluate_not_quarter_end(node)
    when "pct_change_gt"    then evaluate_pct_change(node, :gt)
    when "pct_change_lt"    then evaluate_pct_change(node, :lt)
    when "gt"               then resolve_field(node["field"]).to_f > resolve_param_or_value(node)
    when "lt"               then resolve_field(node["field"]).to_f < resolve_param_or_value(node)
    when "eq"               then resolve_field(node["field"]).to_s == resolve_param_or_value(node).to_s
    when "blank"            then resolve_field(node["field"]).blank?
    when "not_blank"        then !resolve_field(node["field"]).blank?
    else
      # Unknown operator — do not fire the rule to avoid false positives
      Rails.logger.warn("[ConditionTreeEvaluator] Unknown operator: #{op}")
      false
    end
  end

  # Fires when the date is present but NOT the last day of Mar/Jun/Sep/Dec
  def evaluate_not_quarter_end(node)
    raw = resolve_field(node["field"])
    return false if raw.blank?

    date = raw.to_date rescue return(false)
    !quarter_end?(date)
  end

  # Fires when |% change| from compare_to exceeds the threshold param.
  # direction :gt = large increase fires; :lt = large decrease fires.
  def evaluate_pct_change(node, direction)
    current  = resolve_field(node["field"]).to_f
    previous = resolve_field(node["compare_to"]).to_f
    threshold = resolve_param_or_value(node).to_f

    Rails.logger.debug do
      "[ConditionTree] pct_change_#{direction}: field=#{node['field']} " \
        "current=#{current} compare_to=#{node['compare_to']} previous=#{previous} " \
        "threshold=#{threshold}"
    end

    # Cannot compare without a previous value — don't fire the rule
    return false if previous.zero?

    pct_change = ((current - previous) / previous.abs) * 100

    Rails.logger.debug { "[ConditionTree] pct_change=#{pct_change.round(2)}%" }

    case direction
    when :gt then pct_change > threshold           # big positive jump
    when :lt then pct_change < -threshold.abs      # big negative drop
    end
  end

  # ── Field / param resolution ─────────────────────────────────────────────────

  # Fields prefixed "context." come from the ContextProvider output;
  # all others are read directly from the record's attributes.
  def resolve_field(field)
    return nil if field.blank?

    if field.start_with?("context.")
      key = field.delete_prefix("context.")
      @context[key]
    else
      # Use public_send so decorated/virtual attributes work too;
      # fall back to read_attribute for columns that aren't exposed as methods
      begin
        @record.public_send(field)
      rescue NoMethodError
        @record.read_attribute(field)
      end
    end
  end

  # If the node names a param, look it up in the resolved params hash.
  # Otherwise fall back to the inline "value" key (for literal comparisons).
  def resolve_param_or_value(node)
    if node["param"].present?
      @params[node["param"]]
    else
      node["value"]
    end
  end

  # ── Date helpers ─────────────────────────────────────────────────────────────

  def quarter_end?(date)
    QUARTER_END_MONTHS.include?(date.month) && date == date.end_of_month
  end
end
