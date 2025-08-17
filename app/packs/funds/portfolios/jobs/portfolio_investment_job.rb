class PortfolioInvestmentJob < ApplicationJob
  queue_as :low

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(id)
    Chewy.strategy(:sidekiq) do
      portfolio_investment = PortfolioInvestment.find(id)
      portfolio_investment.setup_attribution
    end
  end
end
