# Determines whether to calculate at the portfolio, capital commitment, or investor KYC level,
# and returns the corresponding calculator instance along with the relevant model object.
class FundRatioCalcInitializer
  # Initializes and returns the appropriate calculator for the given fund, commitment, and reporting date.
  #
  # Calculates financial metrics (DPI, RVPI, TVPI, XIRR, etc.) at the appropriate aggregation level:
  # - Portfolio level: Aggregates across all commitments when no specific commitment is provided
  # - Commitment level: Calculates for a single capital commitment
  # - Investor KYC level: Aggregates across all commitments for a KYC when KYC-level reporting is enabled
  #
  # @param fund [Fund] The fund to calculate metrics for
  # @param capital_commitment [CapitalCommitment, nil] Optional specific commitment; nil for portfolio-level calculation
  # @param end_date [Date] The reporting date up to which metrics are calculated
  #
  # @return [Array<Object, Object>] A tuple containing:
  #   - Calculator instance (FundPortfolioCalcs, CapitalCommitmentCalcs, or InvestorKycCalcs)
  #   - Model object (fund, capital_commitment, or investor_kyc)
  #
  # @raises [RuntimeError] If the capital commitment does not belong to the specified fund
  def self.call(fund, capital_commitment, end_date)
    if capital_commitment.present?
      # Validate that the commitment belongs to the fund
      raise "Capital Commitment #{capital_commitment.id} does not belong to Fund #{fund.id}" if capital_commitment.fund_id != fund.id

      # Return investor KYC-level calculations if KYC-level document generation is enabled
      if fund.kyc_level_data_gen?
        [InvestorKycCalcs.new(capital_commitment, end_date), capital_commitment.investor_kyc]
      else
        # Return individual commitment-level calculations
        [CapitalCommitmentCalcs.new(capital_commitment, end_date), capital_commitment]
      end
    else
      # Return fund portfolio-level calculations (all commitments aggregated)
      [FundPortfolioCalcs.new(fund, end_date), fund]
    end
  end
end
