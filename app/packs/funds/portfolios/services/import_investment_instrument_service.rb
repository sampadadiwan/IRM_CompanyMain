class ImportInvestmentInstrumentService < ImportServiceBase
  step :read_file
  step Subprocess(ImportInvestmentInstrument)
  step :save_results_file
end
