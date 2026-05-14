module CapitalCommitmentShared
  extend ActiveSupport::Concern

  included do
    include Memoized
    include CommitmentAccountEntry

    scope :lp_onboarding_complete, -> { where(onboarding_completed: true) }
    scope :lp_onboarding_incomplete, -> { where(onboarding_completed: false) }

    # Returns the commitments of type gp for the fund using unit_type
    # Used in FundTemplateDecorator
    scope :gp, lambda { |fund_id|
      joins("INNER JOIN fund_unit_settings ON fund_unit_settings.fund_id = capital_commitments.fund_id")
        .where(fund_unit_settings: { gp_units: true, fund_id: fund_id })
        .where("fund_unit_settings.name = capital_commitments.unit_type")
    }

    # Returns the commitments of type lp for the fund using unit_type
    scope :lp, lambda { |fund_id|
      joins("INNER JOIN fund_unit_settings ON fund_unit_settings.fund_id = capital_commitments.fund_id")
        .where(fund_unit_settings: { gp_units: false, fund_id: fund_id })
        .where("fund_unit_settings.name = capital_commitments.unit_type")
    }

    # This is used to improve the performance of the formulas, in allocations
    memoize :get_account_entry, :cumulative_account_entry, :on_date, :quarterly, :since_inception
  end

  def pending_call_amount
    call_amount - collected_amount
  end

  def pending_committed_amount
    committed_amount - collected_amount
  end

  def uncalled_amount
    committed_amount - call_amount
  end

  def percentage_pending_call
    call_amount_cents.positive? ? (100 * collected_amount_cents / call_amount_cents).to_f.round(2) : 0
  end

  def called_capital_percentage
    committed_amount_cents.positive? ? (100 * call_amount_cents / committed_amount_cents).to_f.round(2) : 0
  end

  def uncalled_capital_percentage
    committed_amount_cents.positive? ? (100 * uncalled_amount.cents / committed_amount_cents).to_f.round(2) : 0
  end

  def percentage_pending_committed
    committed_amount_cents.positive? ? (100 * collected_amount_cents / committed_amount_cents).to_f.round(2) : 0
  end

  def unfunded_commitment_as_of(end_date, folio_currency: false, tracking_currency: false)
    crps = capital_remittance_payments.where(payment_date: ..end_date)
    crp_amount = if folio_currency
                   crps.sum(:folio_amount_cents)
                 elsif tracking_currency
                   crps.sum(:tracking_amount_cents)
                 else
                   crps.sum(:amount_cents)
                 end

    committed_amount_cents_before(end_date, folio_currency: folio_currency, tracking_currency: tracking_currency) - crp_amount
  end

  def committed_amount_cents_before(date, folio_currency: false, tracking_currency: false)
    date = Date.local_parse(date) if date.is_a?(String)

    # If the commitment date is after the date, then there is no commitment before the date
    return 0 if commitment_date.blank? || commitment_date > date

    # Get the top up adjustments before the date
    adjustments = commitment_adjustments.for_type(["Top Up", "Transfer", "Exchange Rate"]).where(as_of: ..date)
    # Get the committed amount before the date
    if folio_currency
      orig_folio_committed_amount_cents + adjustments.sum(:folio_amount_cents)
    elsif tracking_currency
      orig_tracking_committed_amount_cents + adjustments.sum(:tracking_amount_cents)
    else
      orig_committed_amount_cents + adjustments.sum(:amount_cents)
    end
  end

  def tracking_exchange_rate_date
    commitment_date
  end

  def amounts_and_multipliers(individual_account_entries, basis_code: nil)
    # Calculate multipliers for each account entry based on the given basis_code
    multipliers = individual_account_entries.map do |ae|
      # Get the raw code from the account entry's custom fields (e.g., "UDR 1")
      code = ae.custom_fields.send(basis_code)

      # Convert the code into a normalized snake_case key (e.g., "udr_1")
      key = FormCustomField.to_name(code) if code

      # Safely fetch and convert the corresponding multiplier from custom_fields
      begin
        custom_fields[key].to_d
      rescue StandardError
        0
      end
    end

    # Collect all amount_cents values from the account entries
    amounts = individual_account_entries.map(&:amount_cents)

    # Return both arrays as a tuple: [multipliers, amounts]
    [multipliers, amounts]
  end

  def fund_unit_setting
    fund.fund_unit_settings.where(name: unit_type).last
  end

  # Computes the hurdle amount (preferred return) for the commitment as of a given end date.
  # The hurdle is calculated as: sum(payment_amount * hurdle_rate * (days_outstanding / 365))
  # @param end_date [Date, String] The date up to which the hurdle is calculated.
  # @param use_tracking_currency [Boolean] Whether to use tracking currency instead of the base currency.
  # @param use_distributions [Boolean] Whether to subtract the hurdle calculated on distributions.
  def compute_hurdle(end_date, use_tracking_currency: false, use_distributions: false)
    # Ensure end_date is a Date object for calculations
    end_date = end_date.to_date
    hurdle_rate = fund_unit_setting.json_fields['hurdle_rate'].to_d

    Rails.logger.debug "[Hurdle] Computing hurdle for commitment #{id} as of #{end_date}"
    Rails.logger.debug "[Hurdle] Hurdle rate: #{hurdle_rate}"

    # Calculate hurdle on contributions (remittances)
    hurdle_amount = calculate_hurdle_for_payments(
      capital_remittance_payments.where(payment_date: ..end_date),
      end_date,
      hurdle_rate,
      amount_column: use_tracking_currency ? :tracking_amount_cents : :amount_cents,
      label: "Contributions"
    )

    if use_distributions
      # Subtract hurdle calculated on distributions
      dist_hurdle = calculate_hurdle_for_payments(
        capital_distribution_payments.where(payment_date: ..end_date),
        end_date,
        hurdle_rate,
        amount_column: use_tracking_currency ? :tracking_gross_payable_cents : :gross_payable_cents,
        label: "Distributions"
      )
      hurdle_amount -= dist_hurdle
    end

    Rails.logger.debug "[Hurdle] Final calculated hurdle amount: #{hurdle_amount}"
    hurdle_amount
  end

  private

  # Helper to calculate hurdle for a collection of payments
  def calculate_hurdle_for_payments(payments, end_date, hurdle_rate, amount_column:, label: "Payments")
    Rails.logger.debug "[Hurdle] Processing #{label} (#{payments.count} records)"

    total_hurdle = payments.sum do |payment|
      amount = payment.send(amount_column)
      payment_date = payment.payment_date.to_date

      # IRR/Hurdle standard calculation: Amount * ((1 + Rate)^(Days/365) - 1)
      # This calculates the EARNED preferred return over the period.
      days = (end_date - payment_date).to_i + 1

      # Using (1 + r)^t - 1 formula for compound interest hurdle
      calculation = amount.to_d * (((1 + hurdle_rate) ** (days / 365.0)) - 1)

      Rails.logger.debug "[Hurdle]   - Payment ID: #{payment.id}, Date: #{payment_date}, Amount: #{amount}, Days: #{days}, Hurdle: #{calculation.to_f}"

      calculation
    end

    Rails.logger.debug "[Hurdle] Total hurdle for #{label}: #{total_hurdle.to_f}"
    total_hurdle
  end
end
