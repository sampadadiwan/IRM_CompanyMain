# 1. This is not actuall fees. It basically account entries within a date which are bucketed into different types ["FV For Redemption", "Income", "Expense", "Tax"]
# 2. These account entries are added (Income) or subtracted (Tax , Expense) to the income_with_fees_cents or cost_of_investment_with_fees_cents
# 3. The net_payable_cents is the sum of income_cents, net_ae_cents and cost_of_investment_cents
# 4. Fees is a bad naming used, its just account entries that are bucketed into different types
module CapitalDistributionFees
  extend ActiveSupport::Concern
  include CurrencyHelper

  def setup_distribution_fees
    # Sum of the account_entries ex taxes and expenses
    net_ae_cents = 0
    # Sum of the account_entries without excluding taxes and expenses
    gross_ae_cents = 0

    # The ae_audit field is used to store the audit trail of account entries used for fees computed
    json_fields["ae_audit"] = []

    # Set the income_with_fees_cents and cost_of_investment_with_fees_cents to the original values
    self.income_with_fees_cents = income_cents
    self.cost_of_investment_with_fees_cents = cost_of_investment_cents
    self.reinvestment_with_fees_cents = reinvestment_cents

    capital_distribution.distribution_fees.order(fee_type: :asc).each do |distribution_fee|
      Rails.logger.debug { "Processing distribution_fee: #{distribution_fee.name} for capital_distribution_payment: #{id}" }

      cd_account_entries = capital_commitment.account_entries.where(
        "account_entries.reporting_date >=? AND account_entries.reporting_date <=? AND account_entries.name = ? AND cumulative = ?",
        distribution_fee.start_date, distribution_fee.end_date, distribution_fee.name, false
      )
      # Sum the amount for the fee for the commitment account_entries
      ae_cents = cd_account_entries.sum(:amount_cents)
      # Get the audit trail to display of the account_entries for the fee
      ae_audit = cd_account_entries.map { |a| [a.name, a.reporting_date, a.amount_cents, distribution_fee.fee_type] }

      Rails.logger.debug { "Fees for #{distribution_fee.name} is #{ae_cents} #{ae_audit} for capital_distribution_payment: #{id}" }

      next if ae_audit.blank?

      # Allocate the fees to the correct field based on the fee type

      case distribution_fee.fee_type
      when "Income"
        # Add the fees to the income_with_fees_cents
        self.income_with_fees_cents += ae_cents
        net_ae_cents += ae_cents
        gross_ae_cents += ae_cents
      when "FV For Redemption"
        # Add the fees to the cost_of_investment_with_fees_cents
        self.cost_of_investment_with_fees_cents += ae_cents
        net_ae_cents += ae_cents
        gross_ae_cents += ae_cents
      when "Reinvestment"
        # Add the fees to the reinvestment_with_fees_cents
        self.reinvestment_with_fees_cents += ae_cents
        net_ae_cents += ae_cents
        gross_ae_cents += ae_cents
      when "Tax", "Expense"
        # Subtract the fees from the income_with_fees_cents
        self.income_with_fees_cents -= ae_cents
        net_ae_cents -= ae_cents
        # We do not reduce the gross_ae_cents as we want to show the total
      else
        Rails.logger.debug { "Unknown fee type: #{distribution_fee.fee_type}, not adding to income_with_fees_cents or cost_of_investment_with_fees_cents" }
      end

      json_fields[FormCustomField.to_name(distribution_fee.name)] = currency_from_cents(ae_cents, fund.currency, {})
      json_fields["ae_audit"] << ae_audit if ae_audit.present?
    end

    # Set the net_ae_cents computed above to the net_of_account_entries_cents field
    self.net_of_account_entries_cents = net_ae_cents
    self.gross_of_account_entries_cents = gross_ae_cents

    # Set the net_payable_cents to the sum of income_cents, net_ae_cents and cost_of_investment_cents
    # The net_ae_cents contains the amounts added to the income_with_fees_cents and cost_of_investment_with_fees_cents
    self.net_payable_cents = income_cents + net_ae_cents + cost_of_investment_cents - reinvestment_with_fees_cents
    self.gross_payable_cents = income_cents + gross_ae_cents + cost_of_investment_cents
  end
end
