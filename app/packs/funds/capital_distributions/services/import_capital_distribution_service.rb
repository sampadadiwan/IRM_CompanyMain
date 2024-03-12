class ImportCapitalDistributionService < ImportServiceBase
  step :read_file
  step Subprocess(ImportCapitalDistribution)
  step :save_results_file
end
