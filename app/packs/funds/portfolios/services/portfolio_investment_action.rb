class PortfolioInvestmentAction < Trailblazer::Operation
  def set_valuation(ctx, portfolio_investment:, **)
    if ctx[:valuation].present?
      portfolio_investment.valuation = ctx[:valuation]
    else
      # Find a valuation thats the latest for the portfolio investment
      portfolio_investment.valuation = portfolio_investment.valuations.order(valuation_date: :desc).first
    end
    true
  end

  def compute_amount_cents(_ctx, portfolio_investment:, **)
    portfolio_investment.compute_amount_cents
    true
  end

  def compute_quantity_as_of_date(_ctx, portfolio_investment:, **)
    portfolio_investment.compute_quantity_as_of_date
  end

  def compute_all_numbers(_ctx, portfolio_investment:, **)
    portfolio_investment.compute_all_numbers
  end

  def compute_avg_cost(_ctx, portfolio_investment:, **)
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
