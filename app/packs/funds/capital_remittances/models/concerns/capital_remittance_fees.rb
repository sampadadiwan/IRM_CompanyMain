module CapitalRemittanceFees
  extend ActiveSupport::Concern

  def convert_fees
    if capital_call.call_basis == "Upload"
      # Also for some calls, fees will be included. In uploads the fee is in folio_currency so we convert to fund_currency
      self.capital_fee_cents = folio_capital_fee_cents.positive? ? convert_currency(capital_commitment.folio_currency, fund.currency, folio_capital_fee_cents, remittance_date) : 0

      self.other_fee_cents = folio_other_fee_cents.positive? ? convert_currency(capital_commitment.folio_currency, fund.currency, folio_other_fee_cents, remittance_date) : 0
    else
      # Also for some calls, fees will be included so we convert to folio_currency
      self.folio_capital_fee_cents = capital_fee_cents.positive? ? convert_currency(fund.currency, capital_commitment.folio_currency, capital_fee_cents, remittance_date) : 0

      self.folio_other_fee_cents = other_fee_cents.positive? ? convert_currency(fund.currency, capital_commitment.folio_currency, other_fee_cents, remittance_date) : 0
    end
  end

  # Called whenever remittance is created, to ensure that the fees is populated from the account_entries
  # The account_entries in turn are populated either manually or via fund formulas
  def setup_call_fees
    total_capital_fees_cents = 0
    total_other_fees_cents = 0

    if capital_call.call_fees.present?

      capital_call.call_fees.each do |call_fee|
        # Sum the amount for the fee for the commitment account_entries
        fees = capital_commitment.account_entries.where("account_entries.reporting_date >=? and account_entries.reporting_date <=? and account_entries.name = ? and cumulative = ?", call_fee.start_date, call_fee.end_date, call_fee.name, false).sum(:amount_cents)
        fees_audit = capital_commitment.account_entries.where("account_entries.reporting_date >=? and account_entries.reporting_date <=? and account_entries.name = ? and cumulative = ?", call_fee.start_date, call_fee.end_date, call_fee.name, false).map { |a| [a.name, a.reporting_date, a.amount.to_d] }

        if call_fee.fee_type == "Other Fees"
          total_other_fees_cents += fees
          json_fields["other_fees_audit"] ||= []
          json_fields["other_fees_audit"] << fees_audit if fees_audit.present?
        else
          total_capital_fees_cents += fees
          json_fields["capital_fees_audit"] ||= []
          json_fields["capital_fees_audit"] << fees_audit if fees_audit.present?
        end
      end

      # Flatten the array of arrays
      json_fields["capital_fees_audit"] = json_fields["capital_fees_audit"].flatten if json_fields["capital_fees_audit"].present?
      json_fields["other_fees_audit"] = json_fields["other_fees_audit"].flatten if json_fields["other_fees_audit"].present?

    end

    Rails.logger.debug { "### #{investor_name} total_capital_fees_cents: #{total_capital_fees_cents}, total_other_fees_cents: #{total_other_fees_cents}" }

    self.capital_fee_cents = total_capital_fees_cents
    self.other_fee_cents = total_other_fees_cents
  end

  # Convinience method used in fund formulas. Not used directly in computed_amount
  # DO NOT EVER DELETE THIS METHOD
  def management_fees_days(start_date, end_date)
    if capital_call.due_date <= start_date
      (end_date - start_date).to_i + 1
    elsif capital_call.due_date <= end_date
      (end_date - remittance_date).to_i + 1
    else
      0
    end
  end
end
