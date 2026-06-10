class InvestorKycCalcs < FundRatioCalcs
  delegate :ratio_formulas, to: :@fund

  # Initializes the KYC calculations for a given capital commitment and end date.
  # Sets up references to the related fund, investor KYC, and filters commitment IDs by fund.
  #
  # @param capital_commitment [CapitalCommitment] The capital commitment to calculate metrics for
  # @param end_date [Date] The date up to which metrics should be calculated
  # @raises [RuntimeError] If investor KYC is not found for the capital commitment
  def initialize(capital_commitment, end_date)
    @capital_commitment = capital_commitment
    @fund = capital_commitment.fund
    @investor_kyc = capital_commitment.investor_kyc
    @compute_at_kyc_level = true
    raise "Investor KYC not found for Capital Commitment #{@capital_commitment.id}" unless @investor_kyc

    @kyc_commitment_ids = @investor_kyc.capital_commitments.where(fund_id: @fund.id).pluck(:id)
    @folio_ids = @investor_kyc.capital_commitments.where(fund_id: @fund.id).pluck(:folio_id).uniq

    @model = @capital_commitment
    @end_date = end_date
    super()
  end

  # Override delegated methods to return KYC-specific filtered collections
  def capital_remittance_payments
    @capital_remittance_payments ||= @fund.capital_remittance_payments.joins(:capital_remittance).where(capital_remittances: { capital_commitment_id: @kyc_commitment_ids })
  end

  def capital_distribution_payments
    @capital_distribution_payments ||= @fund.capital_distribution_payments.where(capital_commitment_id: @kyc_commitment_ids)
  end

  # Calculates the Fair Market Value (FMV) in cents for the investor's portfolio.
  # Aggregates FMV from the latest non-cumulative portfolio account entries for all related
  # capital commitments within the investor's KYC, up to the specified end date.
  #
  # Note: Non-cumulative flag ensures individual period values; fund-level filtering provides safety.
  #
  # @return [Integer] Total portfolio FMV in cents
  def fmv_cents
    @fmv_cents ||= begin
      aes = @fund.account_entries.where(name: "Portfolio FMV", fund_id: @fund.id, capital_commitment_id: @kyc_commitment_ids, cumulative: false, reporting_date: ..@end_date)
      latest_per_commitment(aes).sum(:amount_cents)
    end
  end

  # Calculates the total cash in hand in cents for the investor's portfolio.
  # Sums the latest non-cumulative "Cash In Hand" account entries across all related
  # capital commitments within the investor's KYC, up to the specified end date.
  #
  # @return [Integer] Total cash in hand in cents
  def cash_in_hand_cents
    @cash_in_hand_cents ||= begin
      aes = @fund.account_entries.where(name: "Cash In Hand", fund_id: @fund.id, capital_commitment_id: @kyc_commitment_ids, cumulative: false, reporting_date: ..@end_date)
      latest_per_commitment(aes).sum(:amount_cents)
    end
  end

  # Calculates net current assets in cents for the investor's portfolio.
  # Aggregates the latest non-cumulative "Net Current Assets" account entries for all
  # related capital commitments within the investor's KYC, up to the specified end date.
  #
  # @return [Integer] Total net current assets in cents
  def net_current_assets_cents
    @net_current_assets_cents ||= begin
      aes = @fund.account_entries.where(name: "Net Current Assets", cumulative: false, fund_id: @fund.id, capital_commitment_id: @kyc_commitment_ids, reporting_date: ..@end_date)
      latest_per_commitment(aes).sum(:amount_cents)
    end
  end

  # Calculates the estimated carry amount in cents for the investor's portfolio.
  # Sums the latest non-cumulative "Estimated Carry" account entries across all related
  # capital commitments within the investor's KYC, up to the specified end date.
  #
  # @return [Integer] Total estimated carry in cents
  def estimated_carry_cents
    @estimated_carry_cents ||= begin
      aes = @fund.account_entries.where(name: "Estimated Carry", fund_id: @fund.id, capital_commitment_id: @kyc_commitment_ids, cumulative: false, reporting_date: ..@end_date)
      latest_per_commitment(aes).sum(:amount_cents)
    end
  end

  # Calculates the total collected/called capital in cents for the investor's portfolio.
  # Sums verified capital remittances across all related capital commitments, up to the end date.
  #
  # @return [Integer] Total collected capital in cents
  def collected_cents
    @collected_cents ||=
      @fund.capital_remittances.verified.where(capital_commitment_id: @kyc_commitment_ids, remittance_date: ..@end_date).sum(:collected_amount_cents)
  end

  # Calculates the total distributions paid to the investor in cents.
  # Sums net payable amounts from completed capital distribution payments across all related
  # capital commitments, up to the specified end date.
  #
  # @return [Integer] Total distributions in cents
  def distribution_cents
    @distribution_cents ||=
      @fund.capital_distribution_payments.completed.where(capital_commitment_id: @kyc_commitment_ids, payment_date: ..@end_date).sum(:net_payable_cents)
  end

  # Calculates the Distributions Per Dollar Invested (DPI) ratio.
  # DPI = Total Distributions / Total Capital Called
  # Represents the amount of cash returned to the investor per dollar invested.
  # Returns 0 if collected capital is zero.
  #
  # @param use_tracking_currency [Boolean] Whether to apply static formula adjustments
  # @return [Float] DPI ratio
  def dpi(use_tracking_currency: false)
    cc = collected_cents
    dc = distribution_cents
    dc, cc = apply_static_formulas('DPI', dc, cc, use_tracking_currency)
    cc.positive? ? (dc / cc.to_f) : 0
  end

  # Calculates the Residual Value Per Dollar Invested (RVPI) ratio.
  # RVPI = (Portfolio FMV + Cash + Net Current Assets) / Total Capital Called
  # Represents the unrealized value remaining in the portfolio per dollar invested.
  # Returns 0 if collected capital is zero.
  #
  # @param use_tracking_currency [Boolean] Whether to apply static formula adjustments
  # @return [Float] RVPI ratio
  def rvpi(use_tracking_currency: false)
    cc = collected_cents
    total_val = fmv_cents + cash_in_hand_cents + net_current_assets_cents
    total_val, cc = apply_static_formulas('RVPI', total_val, cc, use_tracking_currency)
    cc.positive? ? (total_val / cc.to_f) : 0
  end

  # Calculates the Total Value Per Dollar Invested (TVPI) ratio.
  # TVPI = (Distributions + Portfolio FMV + Cash + Net Current Assets) / Total Capital Called
  # Represents the total value (realized + unrealized) returned per dollar invested.
  # Returns 0 if collected capital is zero. TVPI = DPI + RVPI.
  #
  # @param use_tracking_currency [Boolean] Whether to apply static formula adjustments
  # @return [Float] TVPI ratio
  def tvpi(use_tracking_currency: false)
    cc = collected_cents
    dc = distribution_cents
    rv = fmv_cents + cash_in_hand_cents + net_current_assets_cents

    numerator = dc + rv
    numerator, cc = apply_static_formulas('TVPI', numerator, cc, use_tracking_currency)
    cc.positive? ? (numerator / cc.to_f) : 0
  end

  # Retrieves the most recent Fair Market Value (FMV) across all of the investor's commitments in this fund on or before the end date.
  # Uses the latest non-cumulative "Portfolio FMV" account entry per commitment (by reporting_date, then id).
  #
  # @return [Integer] Total portfolio FMV in cents, or 0 if not found
  def fmv_on_date
    @fmv_on_date ||= begin
      aes = @fund.account_entries.where(name: "Portfolio FMV", fund_id: @fund.id, capital_commitment_id: @kyc_commitment_ids, cumulative: false, reporting_date: ..@end_date)
      latest_per_commitment(aes).sum(:amount_cents)
    end
  end

  # Calculates the Extended Internal Rate of Return (XIRR) for the investor's capital commitment.
  # Delegates to parent FundRatioCalcs class with capital commitment as the model.
  # Supports multiple calculation modes: gross/net IRR, cash flow details, scenario analysis.
  #
  # @param net_irr [Boolean] Calculate net IRR (after fees) vs gross IRR. Default: false (gross)
  # @param return_cash_flows [Boolean] Include cash flow details in response. Default: false
  # @param adjustment_cash [Integer] Optional cash adjustment in cents. Default: 0
  # @param scenarios [Hash] Optional scenario parameters for sensitivity analysis
  # @param use_tracking_currency [Boolean] Apply static formula adjustments using tracking currency
  # @return [Float] XIRR percentage as a decimal (e.g., 0.15 for 15%)
  def xirr(net_irr: false, return_cash_flows: false, adjustment_cash: 0, scenarios: nil, use_tracking_currency: false)
    super(model: @capital_commitment, net_irr:, return_cash_flows:, adjustment_cash:, scenarios:, use_tracking_currency:)
  end
end
