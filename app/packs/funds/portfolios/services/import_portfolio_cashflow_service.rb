class ImportPortfolioCashflowService < ImportServiceBase
  step :read_file
  step Subprocess(ImportPortfolioCashflow)
  step :save_results_file
end
