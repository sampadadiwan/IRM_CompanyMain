class ImportOptionsCustomDataService < ImportServiceBase
  step :read_file
  step Subprocess(ImportOptionsCustomData)
  step :save_results_file
end
