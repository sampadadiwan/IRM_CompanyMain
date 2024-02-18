class PortfolioInvestmentCreate < PortfolioInvestmentAction
  step :setup_aggregate
  left :handle_setup_aggregate_errors
  step :compute_fmv
  step :save
  left :handle_errors
  step :compute_avg_cost
  step :setup_attribution

  # After we save the PI, we need to create the attributions for sells.
  # When we import the data we create it in the same thread, as we need to ensure the attribution is setup before we move on to the next row. However if the portfolio_investment is created by the user, we can do it in the background.
  # Originally we were doing this in the background, but it was causing issues with the attribution being created in parallel and sometimes in the wrong order.
  def setup_attribution(_ctx, portfolio_investment:, **)
    if portfolio_investment.sell?
      portfolio_investment.created_by_import ? PortfolioInvestmentJob.perform_now(portfolio_investment.id) : PortfolioInvestmentJob.perform_later(portfolio_investment.id)
    end
    true
  end

  def setup_aggregate(_ctx, portfolio_investment:, **)
    portfolio_investment.setup_aggregate
  end
end
