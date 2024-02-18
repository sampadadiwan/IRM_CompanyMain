class PortfolioInvestmentUpdate < PortfolioInvestmentAction
  step :compute_fmv
  step :save
  left :handle_errors
  step :compute_avg_cost
end
