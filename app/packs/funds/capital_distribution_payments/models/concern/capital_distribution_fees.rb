module CapitalDistributionFees
  extend ActiveSupport::Concern
  include CurrencyHelper

  def setup_distribution_fees
    total_fee_cents = 0
    json_fields["fees_audit"] = []

    if capital_distribution.distribution_fees.present?
      capital_distribution.distribution_fees.each do |distribution_fee|
        if distribution_fee.formula
          fees_cents = distribution_fee.calculate_formula(self)
          fees_audit = [[distribution_fee.name, distribution_fee.start_date, fees_cents]]
        else
          # Sum the amount for the fee for the commitment account_entries
          fees_cents = capital_commitment.account_entries.where(
            "account_entries.reporting_date >=? AND account_entries.reporting_date <=? AND account_entries.name = ? AND cumulative = ?",
            distribution_fee.start_date, distribution_fee.end_date, distribution_fee.name, false
          ).sum(:amount_cents)

          fees_audit = capital_commitment.account_entries.where(
            "account_entries.reporting_date >=? AND account_entries.reporting_date <=? AND account_entries.name = ? AND cumulative = ?",
            distribution_fee.start_date, distribution_fee.end_date, distribution_fee.name, false
          ).map { |a| [a.name, a.reporting_date, a.amount_cents] }
        end

        next if fees_audit.blank?

        total_fee_cents += fees_cents
        json_fields[FormCustomField.to_name(distribution_fee.name)] = currency_from_cents(fees_cents, fund.currency, {})
        json_fields["fees_audit"] << fees_audit if fees_audit.present?
      end

      self.fee_cents = total_fee_cents
    end

    self.total_amount_cents = amount_cents + total_fee_cents
  end
end
