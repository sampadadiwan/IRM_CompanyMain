class ImportInvestmentService < ImportServiceBase
  step :read_file
  step Subprocess(ImportInvestment)
  step :save_results_file
end
