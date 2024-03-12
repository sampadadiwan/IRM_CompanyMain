class ImportKpiService < ImportServiceBase
  step :read_file
  step Subprocess(ImportKpi)
  step :save_results_file
end
