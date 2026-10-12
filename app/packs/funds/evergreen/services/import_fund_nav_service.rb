class ImportFundNavService < ImportServiceBase
  step :read_file
  step Subprocess(ImportFundNav)
  step :save_results_file
end
