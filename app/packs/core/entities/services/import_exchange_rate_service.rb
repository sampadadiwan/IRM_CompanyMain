class ImportExchangeRateService < ImportServiceBase
  step :read_file
  step Subprocess(ImportExchangeRate)
  step :save_results_file
end
