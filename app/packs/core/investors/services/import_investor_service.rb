class ImportInvestorService < ImportServiceBase
  step :read_file
  step Subprocess(ImportInvestor)
  step :save_results_file
end
