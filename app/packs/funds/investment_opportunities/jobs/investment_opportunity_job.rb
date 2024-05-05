class InvestmentOpportunityJob < ApplicationJob
  queue_as :default

  def perform(investment_opportunity_id)
    Chewy.strategy(:active_job) do
      @investment_opportunity = InvestmentOpportunity.find(investment_opportunity_id)

      @investment_opportunity.expression_of_interests.update_all(allocation_amount_cents: 0, allocation_percentage: 0)

      pct = [@investment_opportunity.percentage_raised, 100].max
      @investment_opportunity.expression_of_interests.approved.each do |eoi|
        eoi.allocation_amount_cents = (eoi.amount_cents * 100.0 / pct).floor
        eoi.save
      end
    end
  end
end
