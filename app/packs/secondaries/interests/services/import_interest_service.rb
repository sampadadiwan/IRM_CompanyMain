class ImportInterestService < ImportServiceBase
  step :read_file
  step Subprocess(ImportInterest)
  step :save_results_file
end
