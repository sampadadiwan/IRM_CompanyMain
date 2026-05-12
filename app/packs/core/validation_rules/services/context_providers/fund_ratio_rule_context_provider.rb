# Provides named context values for FundRatio rules.
class FundRatioRuleContextProvider
  # @param record [FundRatio]
  # @param entity [Entity]
  # @return [Hash] symbol-keyed context values
  def call(record:, entity:, params: {})
    prev = find_previous_ratio(record, entity)

    {
      # Most recent prior ratio value for the same fund + form type.
      # Reserved for future out-of-range or large-change trend rules;
      # no current DEFAULT_RULE references this key.
      prev_ratio_value: prev&.value
    }
  end

  private

  def find_previous_ratio(record, entity)
    scope = FundRatio.where(entity:, fund_id: record.fund_id, form_type_id: record.form_type_id)
    scope = scope.where.not(id: record.id) if record.persisted?
    scope.order(created_at: :desc).first
  end
end
