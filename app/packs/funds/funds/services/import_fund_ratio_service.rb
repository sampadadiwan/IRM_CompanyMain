class ImportFundRatioService < ImportServiceBase
  step :read_file
  step Subprocess(ImportFundRatio)
  step :save_results_file
end
