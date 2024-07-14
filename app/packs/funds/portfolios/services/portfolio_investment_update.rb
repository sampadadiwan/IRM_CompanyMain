class PortfolioInvestmentUpdate < PortfolioInvestmentAction
  step :compute_amount_cents
  step :compute_all_numbers
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :compute_avg_cost
end
