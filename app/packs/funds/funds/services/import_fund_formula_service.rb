class ImportFundFormulaService < ImportServiceBase
  step :read_file
  step Subprocess(ImportFundFormula)
  step :save_results_file
end
