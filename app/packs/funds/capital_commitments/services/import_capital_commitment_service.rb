class ImportCapitalCommitmentService < ImportServiceBase
  step :read_file
  step Subprocess(ImportCapitalCommitment)
  step :save_results_file
end
