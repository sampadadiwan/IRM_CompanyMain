class ImportCapitalCallService < ImportServiceBase
  step :read_file
  step Subprocess(ImportCapitalCall)
  step :save_results_file
end
