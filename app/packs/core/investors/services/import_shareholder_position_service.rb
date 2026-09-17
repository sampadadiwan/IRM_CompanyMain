class ImportShareholderPositionService < ImportServiceBase
  step :read_file
  step Subprocess(ImportShareholderPosition)
  step :save_results_file
end