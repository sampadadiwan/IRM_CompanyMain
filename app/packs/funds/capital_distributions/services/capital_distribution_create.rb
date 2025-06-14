class CapitalDistributionCreate < Trailblazer::Operation
  step :save_with_pi

  # rubocop:disable  Rails/SkipsModelValidations
  def save_with_pi(ctx, capital_distribution:, **)
    # This operation saves the capital distribution and updates the portfolio investments with the new capital_distribution_id.
    cd_saved = false, pis_saved = false
    # Ensure both capital_distribution and portfolio_investments are saved in a transaction
    CapitalDistribution.transaction do
      cd_saved = capital_distribution.save
      # If portfolio_investment_ids are provided, update the portfolio investments
      portfolio_investment_ids = ctx[:portfolio_investment_ids]
      if portfolio_investment_ids.present?
        pis = capital_distribution.fund.portfolio_investments.where(id: portfolio_investment_ids)
        pis_saved = pis.update_all(capital_distribution_id: capital_distribution.id).positive?
      end
    end
    # Return true if both capital_distribution and portfolio investments (if any) were saved successfully
    cd_saved && (pis_saved || ctx[:portfolio_investment_ids].blank?)
  end
  # rubocop:enable Rails/SkipsModelValidations
end
