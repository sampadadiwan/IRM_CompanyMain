# Context provider for PortfolioInvestment rules.
#
# The only PortfolioInvestment rule (portfolio_investment_date_out_of_range) reads the record's
# own investment_date, so no context values are needed. ValidationRuleEvaluator requires every
# target model to have a provider, hence this empty one.
class PortfolioInvestmentRuleContextProvider
  # @param record [PortfolioInvestment] Unused
  # @param entity [Entity]              Unused
  # @param params [Hash]                Unused
  # @return [Hash] always empty
  def call(record:, entity:, params: {})
    {}
  end
end
