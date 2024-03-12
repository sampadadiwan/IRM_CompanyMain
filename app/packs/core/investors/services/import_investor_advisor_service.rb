class ImportInvestorAdvisorService < ImportServiceBase
  step :read_file
  step Subprocess(ImportInvestorAdvisor)
  step :save_results_file
end
