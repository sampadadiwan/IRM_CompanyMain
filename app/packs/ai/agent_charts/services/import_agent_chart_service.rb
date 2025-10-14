class ImportAgentChartService < ImportServiceBase
  step :read_file
  step Subprocess(ImportAgentChart)
  step :save_results_file
end
