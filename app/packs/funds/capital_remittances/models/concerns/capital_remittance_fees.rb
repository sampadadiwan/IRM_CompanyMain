module CapitalRemittanceFees
  extend ActiveSupport::Concern

  def setup_call_fees
    total_capital_fees_cents = 0
    total_other_fees_cents = 0

    if capital_call.call_fees.present?

      capital_call.call_fees.each do |call_fee|
        # Sum the amount for the fee for the commitment account_entries
        fees = capital_commitment.account_entries.where("account_entries.reporting_date >=? and account_entries.reporting_date <=? and account_entries.name = ? and cumulative = ?", call_fee.start_date, call_fee.end_date, call_fee.name, false).sum(:amount_cents)

        call_fee.fee_type == "Other Fees" ? total_other_fees_cents += fees : total_capital_fees_cents += fees
      end

    end

    Rails.logger.debug { "### #{investor_name} total_capital_fees_cents: #{total_capital_fees_cents}, total_other_fees_cents: #{total_other_fees_cents}" }

    self.capital_fee_cents = total_capital_fees_cents
    self.other_fee_cents = total_other_fees_cents
  end

  def management_fees_days(start_date, end_date)
    if capital_call.due_date < start_date
      (end_date - start_date).to_i
    elsif capital_call.due_date < end_date
      (end_date - capital_call.due_date).to_i
    else
      0
    end
  end
end
