class PortfolioInvestmentAction < Trailblazer::Operation
  def compute_fmv(_ctx, portfolio_investment:, **)
    portfolio_investment.compute_fmv
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
