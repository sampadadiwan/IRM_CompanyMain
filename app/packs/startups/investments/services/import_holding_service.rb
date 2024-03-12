class ImportHoldingService < ImportServiceBase
  step :read_file
  step Subprocess(ImportHolding)
  step :save_results_file
end
