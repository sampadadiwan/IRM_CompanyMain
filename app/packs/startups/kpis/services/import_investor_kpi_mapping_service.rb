class ImportInvestorKpiMappingService < ImportServiceBase
  step :read_file
  step Subprocess(ImportInvestorKpiMapping)
  step :save_results_file
end
