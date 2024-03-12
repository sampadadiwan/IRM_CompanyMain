class ImportCapitalRemittanceService < ImportServiceBase
  step :read_file
  step Subprocess(ImportCapitalRemittance)
  step :save_results_file
end
