class ImportAccountEntryService < ImportServiceBase
  step :read_file
  step Subprocess(ImportAccountEntry)
  step :save_results_file
end
