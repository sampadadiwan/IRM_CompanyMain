class ImportInvestorAccessService < ImportServiceBase
  step :read_file
  step Subprocess(ImportInvestorAccess)
  step :save_results_file
end
