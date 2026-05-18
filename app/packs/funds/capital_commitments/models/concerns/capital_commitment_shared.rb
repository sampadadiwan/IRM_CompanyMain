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
  # The hurdle is calculated as: sum(payment_amount * ((1 + rate)^(days/365) - 1))
  # @param end_date [Date, String] The date up to which the hurdle is calculated.
  # @param use_tracking_currency [Boolean] Whether to use tracking currency instead of the base currency.
  # @param use_distributions [Boolean] Whether to subtract the hurdle calculated on distributions.
  # @param skip_distribution_for_hurdle [Boolean] If true, ignore distributions where the parent capital_distribution is flagged to skip.
  def compute_hurdle(end_date, use_tracking_currency: false, use_distributions: false, skip_distribution_for_hurdle: false)
    # Ensure end_date is a Date object for calculations
    end_date = end_date.to_date
    hurdle_rate = fund_unit_setting.json_fields['hurdle_rate'].to_d

    Rails.logger.debug "[Hurdle] Computing hurdle for commitment #{id} as of #{end_date}"
    Rails.logger.debug "[Hurdle] Hurdle rate: #{hurdle_rate}"

    remittance_col = use_tracking_currency ? :tracking_amount_cents : :amount_cents
    distribution_col = use_tracking_currency ? :tracking_gross_payable_cents : :gross_payable_cents

    # Step 1: Determine effective_end_date.
    # Default to end_date. When use_distributions is true and total distributions exceed total remittances
    # (i.e. principal fully returned), hurdle stops accruing at the truncated distribution's payment date.
    effective_end_date = end_date
    total_remittance_cents = nil

    if use_distributions
      # Sum all remittances up to end_date — this is the investor's total cost basis (principal).
      total_remittance_cents = capital_remittance_payments.where(payment_date: ..end_date).sum(remittance_col)

      # Build the full distributions relation up to end_date (with optional skip filter) for the lookup.
      all_distributions = capital_distribution_payments.where(payment_date: ..end_date).order(payment_date: :asc)

      # OPTIONAL FILTER: Some distributions (e.g. tax distributions or specific recalls) might
      # need to be excluded from the hurdle calculation entirely.
      if skip_distribution_for_hurdle
        # We join with the parent capital_distribution to check the skip flag in json_fields.
        # This allows us to exclude entire distribution events from the preferred return calculation.
        # Note: We only exclude if explicitly set to 'Yes'. If the field is nil or missing,
        # JSON_EXTRACT returns NULL, and we want to include those (hence the OR condition).
        all_distributions = all_distributions.joins(:capital_distribution)
                                             .where("JSON_EXTRACT(capital_distributions.json_fields, '$.skip_distribution_for_hurdle') IS NULL OR " \
                                                    "JSON_EXTRACT(capital_distributions.json_fields, '$.skip_distribution_for_hurdle') != ?", "Yes")
      end

      # Walk distributions chronologically; the first payment that pushes cumulative above
      # total_remittance_cents is the one where principal is fully returned.
      cumulative_dist_cents = 0
      truncated_dist = all_distributions.find do |dist|
        cumulative_dist_cents += dist.send(distribution_col)
        cumulative_dist_cents > total_remittance_cents
      end

      if truncated_dist
        effective_end_date = truncated_dist.payment_date.to_date
        Rails.logger.debug "[Hurdle] Distributions exceed remittances; effective_end_date capped at #{effective_end_date} (distribution #{truncated_dist.id})"
      end
    end

    Rails.logger.debug "[Hurdle] Effective end date: #{effective_end_date}"

    # Step 2: Query payments scoped to effective_end_date and compute hurdles.
    remittances = capital_remittance_payments.where(payment_date: ..effective_end_date).order(payment_date: :asc)
    hurdle_amount = calculate_hurdle_for_payments(
      remittances,
      effective_end_date,
      hurdle_rate,
      amount_column: remittance_col,
      label: "Contributions"
    )

    if use_distributions
      # USE CASE: Offset hurdle earned on invested capital with distributions received.
      # RULE: Distributions should only offset hurdle on the "Principal" (remittances) paid back.
      # If total distributions exceed total remittances (i.e. investor has received more than their cost basis),
      # we stop calculating "negative hurdle" on the excess. This prevents the hurdle from becoming
      # artificially low or negative when the investment is highly profitable.
      distributions = capital_distribution_payments.where(payment_date: ..effective_end_date).order(payment_date: :asc)

      if skip_distribution_for_hurdle
        distributions = distributions.joins(:capital_distribution)
                                     .where("JSON_EXTRACT(capital_distributions.json_fields, '$.skip_distribution_for_hurdle') IS NULL OR " \
                                            "JSON_EXTRACT(capital_distributions.json_fields, '$.skip_distribution_for_hurdle') != ?", "Yes")
      end

      dist_hurdle = calculate_hurdle_for_payments(
        distributions,
        effective_end_date,
        hurdle_rate,
        amount_column: distribution_col,
        label: "Distributions",
        cap_amount_cents: total_remittance_cents
      )
      hurdle_amount -= dist_hurdle
    end

    Rails.logger.debug "[Hurdle] Final calculated hurdle amount: #{hurdle_amount}"
    hurdle_amount
  end

  private

  # Helper to calculate hurdle for a collection of payments
  # @param cap_amount_cents [Integer] If provided, only calculate hurdle for payments up to this cumulative amount.
  # This is used for distributions to ensure we only offset hurdle up to the principal amount.
  def calculate_hurdle_for_payments(payments, end_date, hurdle_rate, amount_column:, label: "Payments", cap_amount_cents: nil)
    Rails.logger.debug "[Hurdle] Processing #{label} (#{payments.count} records) with cap: #{cap_amount_cents || 'None'}"

    cumulative_amount_cents = 0
    total_hurdle = 0

    payments.each do |payment|
      amount = payment.send(amount_column)

      # If capping is enabled (for distributions), we process payments chronologically
      # until the cumulative amount reaches the cost basis (total remittances).
      if cap_amount_cents
        remaining_cap = cap_amount_cents - cumulative_amount_cents

        # Stop calculating once we've offset all principal.
        break if remaining_cap <= 0

        # If the current distribution payment exceeds the remaining principal,
        # only calculate hurdle on the portion that matches the principal.
        if amount > remaining_cap
          Rails.logger.debug "[Hurdle]   - Payment ID: #{payment.id} truncated from #{amount} to #{remaining_cap} due to principal cap"
          amount = remaining_cap
        end
      end

      payment_date = payment.payment_date.to_date

      # IRR/Hurdle standard calculation: Amount * ((1 + Rate)^(Days/365) - 1)
      # This calculates the EARNED preferred return over the period.
      # Standard financial convention uses (D2 - D1) for the interest period.
      # Days is capped at 0 so that payments after effective_end_date contribute nothing.
      days = [(end_date - payment_date).to_i, 0].max

      # Using (1 + r)^t - 1 formula for compound interest hurdle (XIRR basis).
      calculation = amount.to_d * (((1 + hurdle_rate) ** (days / 365.0)) - 1)

      Rails.logger.debug "[Hurdle]   - Payment ID: #{payment.id}, Date: #{payment_date}, Amount: #{amount}, Days: #{days}, Hurdle: #{calculation.to_f}"

      total_hurdle += calculation
      cumulative_amount_cents += amount
    end

    Rails.logger.debug "[Hurdle] Total hurdle for #{label}: #{total_hurdle.to_f}"
    total_hurdle
  end
end
