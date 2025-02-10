class CapitalDistributionJob < ApplicationJob
  # This job can generate multiple capital remittances, which cause deadlocks. Hence serial process these jobs
  queue_as :serial
  attr_accessor :payments

  # This job is idempotent and can be run multiple times for the same capital_distribution_id
  def perform(capital_distribution_id)
    @payments = []
    Chewy.strategy(:sidekiq) do
      @capital_distribution = CapitalDistribution.find(capital_distribution_id)
      generate_payments
      # This is to ensure the gross_amount is computed correctly, after the payments have been computed
      @capital_distribution.reload.save
    end
  end

  def generate_payments
    fund = @capital_distribution.fund
    capital_commitments = fund.capital_commitments

    # Need to distriute the capital based on the percentage holding of the fund by the investor
    capital_commitments.each do |cc|
      # Compute the amount based on the distribution_percentage of the capital_commitment
      percentage = @capital_distribution.distribution_percentage(cc)

      income_cents = (@capital_distribution.income_cents * percentage / 100.0).round(2)
      cost_of_investment_cents = (@capital_distribution.cost_of_investment_cents * percentage / 100.0).round(2)
      reinvestment_cents = (@capital_distribution.reinvestment_cents * percentage / 100.0).round(2)

      if CapitalDistributionPayment.exists?(capital_distribution_id: @capital_distribution.id, capital_commitment_id: cc.id)
        Rails.logger.debug { "Skipping CapitalDistributionPayment for #{cc}, already exists" }
      else
        payment = CapitalDistributionPayment.new(fund_id: @capital_distribution.fund_id,
                                                 entity_id: @capital_distribution.entity_id,
                                                 capital_distribution_id: @capital_distribution.id,
                                                 capital_commitment_id: cc.id, reinvestment_cents:,
                                                 investor_id: cc.investor_id, cost_of_investment_cents:,
                                                 investor_name: cc.investor_name, income_cents:,
                                                 payment_date: @capital_distribution.distribution_date,
                                                 percentage: percentage.round(2), folio_id: cc.folio_id,
                                                 completed: @capital_distribution.generate_payments_paid)

        CapitalDistributionPayment.skip_counter_culture_updates do
          result = CapitalDistributionPaymentCreate.wtf?(capital_distribution_payment: payment)
          if result.success?
            @payments << payment
            Rails.logger.debug { "Created Payment of #{payment.net_payable} for #{cc.investor_name} id #{payment.id}" }
          else
            Rails.logger.error { "Error creating Payment for #{cc.investor_name} id #{payment.id}" }
            Rails.logger.error { payment.errors.full_messages }
          end
        end
      end
    end

    # Update the counter caches
    CapitalDistributionPayment.counter_culture_fix_counts where: { entity_id: @capital_distribution.entity_id }
  end
end
