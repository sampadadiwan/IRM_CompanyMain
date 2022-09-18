class CapitalDistributionJob < ApplicationJob
  queue_as :default

  # This job is idempotent and can be run multiple times for the same capital_distribution_id
  def perform(capital_distribution_id)
    Chewy.strategy(:sidekiq) do
      @capital_distribution = CapitalDistribution.find(capital_distribution_id)
      funding_round = @capital_distribution.fund.funding_round
      # Need to distriute the capital based on the percentage holding of the fund by the investor
      funding_round.aggregate_investments.includes(:investor).each do |inv|
        # Compute the amount based on the investment % in the fund
        amount_cents = @capital_distribution.net_amount_cents * inv.percentage / 100.0

        # Find if the payment already exists
        payment = CapitalDistributionPayment.where(capital_distribution_id: @capital_distribution.id, investor_id: inv.investor_id).first

        if payment
          # Update the payment
          payment.amount_cents = amount_cents
          payment.save
          logger.debug "Updated Payment of #{amount_cents} cents for #{inv.investor.investor_name} id #{payment.id}"
        else
          # Create a new payment
          payment = CapitalDistributionPayment.create!(fund_id: @capital_distribution.fund_id,
                                                       entity_id: @capital_distribution.entity_id,
                                                       capital_distribution_id: @capital_distribution.id,
                                                       investor_id: inv.investor_id, amount_cents:,
                                                       payment_date: @capital_distribution.distribution_date)

          logger.debug "Created Payment of #{amount_cents} cents for #{inv.investor.investor_name} id #{payment.id}"
        end
      end
    end
  end
end
