# Provides named context values for FundRatioRunTemplate rules evaluated at trigger time.
class FundRatioRunTemplateRuleContextProvider
  # @param record [FundRatioRunTemplate]
  # @param entity [Entity]
  # @return [Hash] symbol-keyed context values
  def call(record:, entity:, params: {})
    { trigger_end_date: record.trigger_end_date }
  end
end
