class AiFundChecksJob < ApplicationJob
  queue_as :default

  def perform(fund_id, user_id, rule_type, schedule)
    # Find the model
    fund = Fund.find(fund_id)

    # Run the compliance checks for all the fund PortfolioInvestment
    fund.portfolio_investments.each do |portfolio_investment|
      AiChecksJob.perform_later('PortfolioInvestment', portfolio_investment.id, user_id, rule_type, schedule)
    end

    # Run the compliance checks for all the fund CapitalCommitment
    fund.capital_commitments.each do |capital_commitment|
      AiChecksJob.perform_later('CapitalCommitment', capital_commitment.id, user_id, rule_type, schedule)
    end
  end
end
