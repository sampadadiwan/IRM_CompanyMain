class PortfolioInvestmentAction < Trailblazer::Operation
  def set_valuation(ctx, portfolio_investment:, **)
    # The latest price this fund accepts (PriceResolver), not simply the latest row (H7)
    accepted = portfolio_investment.fund && portfolio_investment.investment_instrument &&
               PriceResolver.lookup(instrument: portfolio_investment.investment_instrument, owner: portfolio_investment.portfolio_company,
                                    as_of: Time.zone.today, policy: SourcePolicy.for(portfolio_investment.fund))&.valuation
    portfolio_investment.valuation = accepted || ctx[:valuation].presence || portfolio_investment.valuations.order(valuation_date: :desc).first
    true
  end

  def compute_amount_cents(_ctx, portfolio_investment:, **)
    # Ensure fund and investment_instrument are loaded before compute accesses both for currency comparison
    ActiveRecord::Associations::Preloader.new(records: [portfolio_investment], associations: %i[fund investment_instrument]).call if portfolio_investment.persisted? && !portfolio_investment.association(:fund).loaded?
    portfolio_investment.compute_amount_cents
    true
  end

  def compute_quantity_as_of_date(_ctx, portfolio_investment:, **)
    portfolio_investment.compute_quantity_as_of_date
  end

  def compute_all_numbers(_ctx, portfolio_investment:, **)
    portfolio_investment.compute_all_numbers
  end

  # skip_aggregate_save: passed by ImportPortfolioInvestment, whose post_process re-saves every aggregate of the
  # fund once the rows are in (and runs even when a fail-fast import stops early). Re-saving the aggregate
  # after every imported investment only produced intermediate states (D4, approved 2026-10-22; E10).
  # A Trailblazer step, so its result still decides the row: the skipped save could only fail on the aggregate's
  # validations (no before_validation, and before_save can't halt it), so the same reload + valid? gives the same
  # pass / fail - and leaves the aggregate reloaded for the next steps, as before - without the UPDATE and the
  # before_save recomputation.
  def compute_avg_cost(_ctx, portfolio_investment:, skip_aggregate_save: false, **)
    return portfolio_investment.aggregate_portfolio_investment.reload.valid? if skip_aggregate_save

    portfolio_investment.compute_avg_cost
  end

  def save(_ctx, portfolio_investment:, **)
    portfolio_investment.save
  end

  def handle_errors(ctx, portfolio_investment:, **)
    unless portfolio_investment.valid?
      ctx[:errors] = portfolio_investment.errors.full_messages.join(", ")
      Rails.logger.error portfolio_investment.errors.full_messages
    end
    portfolio_investment.valid?
  end

  def handle_setup_aggregate_errors(ctx, portfolio_investment:, **)
    ctx[:errors] = "Error in setting up aggregate portfolio investment for #{portfolio_investment.id}"
    false
  end
end
