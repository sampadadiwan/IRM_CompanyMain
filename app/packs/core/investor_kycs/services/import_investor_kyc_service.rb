class ImportInvestorKycService < ImportServiceBase
  step :read_file
  step Subprocess(ImportInvestorKyc)
  step :save_results_file
end
