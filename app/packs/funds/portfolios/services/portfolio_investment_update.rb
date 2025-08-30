class PortfolioInvestmentUpdate < PortfolioInvestmentAction
  step :set_valuation
  step :compute_amount_cents
  step :compute_all_numbers
  step :compute_quantity_as_of_date
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :compute_avg_cost
end
