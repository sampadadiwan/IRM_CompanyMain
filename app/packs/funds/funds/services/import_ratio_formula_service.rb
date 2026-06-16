class ImportRatioFormulaService < ImportServiceBase
  step :read_file
  step Subprocess(ImportRatioFormula)
  step :save_results_file
end
