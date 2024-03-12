class ImportPortfolioInvestmentService < ImportServiceBase
  step :read_file
  step Subprocess(ImportPortfolioInvestment)
  step :save_results_file
end
