class CapitalDistributionDestroy < Trailblazer::Operation
  step :save_with_pi

  def save_with_pi(_ctx, capital_distribution:, **)
    # Unlink the portfolio investments (they outlive the distribution) and destroy it, atomically
    destroyed = false
    CapitalDistribution.transaction do
      capital_distribution.portfolio_investments.update_all(capital_distribution_id: nil)
      destroyed = capital_distribution.destroy
      # destroy returns false when a before_destroy guard aborts (e.g. fund units allocated) — undo the unlink too
      raise ActiveRecord::Rollback unless destroyed
    end
    destroyed.present?
  end
end
