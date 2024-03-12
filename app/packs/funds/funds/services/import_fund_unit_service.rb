class ImportFundUnitService < ImportServiceBase
  step :read_file
  step Subprocess(ImportFundUnit)
  step :save_results_file
end
