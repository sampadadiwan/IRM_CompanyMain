class CapitalDistributionDestroy < Trailblazer::Operation
  step :save_with_pi

  # rubocop:disable  Rails/SkipsModelValidations
  def save_with_pi(_ctx, capital_distribution:, **)
    # This operation saves the capital distribution and updates the portfolio investments with the new capital_distribution_id.
    cd_saved = false, pis_saved = false
    # Ensure both capital_distribution and portfolio_investments are saved in a transaction
    CapitalDistribution.transaction do
      # If portfolio_investment_ids are provided, update the portfolio investments
      pis_saved = capital_distribution.portfolio_investments.update_all(capital_distribution_id: nil).positive? if capital_distribution.portfolio_investments.present?

      cd_saved = capital_distribution.destroy
    end
    # Return true if both capital_distribution and portfolio investments (if any) were saved successfully
    cd_saved && (pis_saved || capital_distribution.portfolio_investments.blank?)
  end
  # rubocop:enable Rails/SkipsModelValidations
end
