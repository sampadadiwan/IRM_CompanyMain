class ImportAllocationService < ImportServiceBase
  step :read_file
  step Subprocess(ImportAllocation)
  step :save_results_file
end
