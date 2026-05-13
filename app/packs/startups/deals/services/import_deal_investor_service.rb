class ImportDealInvestorService < ImportServiceBase
  step :read_file
  step Subprocess(ImportDealInvestor)
  step :save_results_file
end
