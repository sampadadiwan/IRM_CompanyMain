class CapitalDistributionJob < ApplicationJob
  # This job can generate multiple capital remittances, which cause deadlocks. Hence serial process these jobs
  queue_as :serial
  attr_accessor :payments

  # This job is idempotent and can be run multiple times for the same capital_distribution_id
  def perform(capital_distribution_id)
    @payments = []
    Chewy.strategy(:sidekiq) do
      @capital_distribution = CapitalDistribution.find(capital_distribution_id)
      fund = @capital_distribution.fund
      # Need to distriute the capital based on the percentage holding of the fund by the investor
      fund.capital_commitments.each do |cc|
        # Compute the amount based on the investment % in the fund
        amount_cents = @capital_distribution.net_amount_cents * cc.percentage / 100.0

        if CapitalDistributionPayment.exists?(capital_distribution_id: @capital_distribution.id, capital_commitment_id: cc.id)
          Rails.logger.debug { "Skipping CapitalDistributionPayment for #{cc}, already exists" }
        else
          payment = CapitalDistributionPayment.new(fund_id: @capital_distribution.fund_id,
                                                   entity_id: @capital_distribution.entity_id,
                                                   capital_distribution_id: @capital_distribution.id,
                                                   capital_commitment_id: cc.id,
                                                   investor_id: cc.investor_id,
                                                   investor_name: cc.investor_name, amount_cents:,
                                                   payment_date: @capital_distribution.distribution_date,
                                                   percentage: cc.percentage, folio_id: cc.folio_id,
                                                   completed: @capital_distribution.generate_payments_paid)

          next unless payment.valid?

          payment.run_callbacks(:save) { false }
          payment.run_callbacks(:create) { false }
          @payments << payment
          logger.debug "Created Payment of #{amount_cents} cents for #{cc.investor_name} id #{payment.id}"
        end
      end

      Rails.logger.debug { "Importing #{@payments.length} CapitalDistributionPayment" }
      # import the rows
      CapitalDistributionPayment.import @payments
      # Update the index
      CapitalDistributionPaymentIndex.import(@capital_distribution.capital_distribution_payments)
      # Update the counter caches
      CapitalDistributionPayment.counter_culture_fix_counts
    end
  end
end
