class ImportFundService < ImportServiceBase
  step :read_file
  step Subprocess(ImportFund)
  step :save_results_file
end
