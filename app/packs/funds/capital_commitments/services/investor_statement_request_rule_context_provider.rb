# Context provider for InvestorStatementRequest rules.
#
# The only rule (investor_statement_date_out_of_range) reads the request's own start_date and
# end_date, so no context values are needed. ValidationRuleEvaluator requires every target model
# to have a provider, hence this empty one.
class InvestorStatementRequestRuleContextProvider
  # @param record [InvestorStatementRequest] Unused
  # @param entity [Entity]                   Unused
  # @param params [Hash]                     Unused
  # @return [Hash] always empty
  def call(record:, entity:, params: {})
    {}
  end
end
