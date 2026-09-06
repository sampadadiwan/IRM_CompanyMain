# Provides named context values for FundFormula rules.
#
# No context.* fields are needed yet — the only FundFormula rule so far
# (fund_formula_cumulate_requires_roll_up) checks plain columns (rule_type,
# roll_up) directly on the record. This provider exists only to satisfy
# ValidationRuleEvaluator::CONTEXT_PROVIDERS, whose gate in WithValidationRules
# is all-or-nothing per target_model — without an entry here, FundFormula
# rules would never be evaluated at all, even ones needing no context.
class FundFormulaRuleContextProvider
  # @param record [FundFormula] The formula being validated
  # @param entity [Entity]      Unused — part of the standard provider interface
  # @param params [Hash]        Unused — no parameterised queries for this rule
  # @return [Hash] symbol-keyed context values
  def call(record:, entity:, params: {})
    {}
  end
end
