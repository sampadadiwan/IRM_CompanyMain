class ImportValuationService < ImportServiceBase
  step :read_file
  step Subprocess(ImportValuation)
  step :save_results_file
end
