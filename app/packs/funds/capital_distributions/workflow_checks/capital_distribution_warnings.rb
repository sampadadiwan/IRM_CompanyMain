# Readiness warnings for the capital distribution journey panel: things that won't stop a task from
# passing but mean some investors won't be emailed or paid smoothly. Shown only until investors are
# emailed (or when no email goes out at all) — after that they can't be acted on.
# Worked examples E6 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  class CapitalDistributionWarnings
    include WorkflowChecks::CapitalDistribution::Support

    def initialize(dist)
      @dist = dist
    end

    # Array of warning strings (possibly empty)
    def to_a
      return [] if no_email_reason(@dist) || all_emailed?(@dist)

      [skip_doc_gen_warning, subscriber_warning, bank_details_warning].compact
    end

    private

    def skip_doc_gen_warning
      count = payments(@dist).count - emailable_payments(@dist).count
      return if count.zero?

      "#{count} #{'commitment'.pluralize(count)} #{count == 1 ? 'has' : 'have'} Skip Doc Gen set and will not be emailed"
    end

    # The same recipients CapitalDistributionPayment#send_notification emails. One lookup per distinct
    # investor, and only until investors are emailed.
    def subscriber_warning
      investor_ids = emailable_payments(@dist).distinct.pluck(:investor_id)
      count = ::Investor.where(id: investor_ids).to_a.count { |investor| investor.notification_users(@dist.fund, with_tag: "Distribution").empty? }
      return if count.zero?

      "#{count} #{'investor'.pluralize(count)} #{count == 1 ? 'has' : 'have'} nobody subscribed to Distribution emails"
    end

    # The same rule as DistributionReadinessAgent#verify_bank_details: a bank account on the KYC
    def bank_details_warning
      kyc_ids = ::CapitalCommitment.where(id: payments(@dist).select(:capital_commitment_id)).select(:investor_kyc_id)
      count = ::InvestorKyc.where(id: kyc_ids).where(bank_account_number: [nil, ""]).count
      return if count.zero?

      "#{count} #{'KYC'.pluralize(count)} #{count == 1 ? 'has' : 'have'} no bank account number"
    end
  end
end
