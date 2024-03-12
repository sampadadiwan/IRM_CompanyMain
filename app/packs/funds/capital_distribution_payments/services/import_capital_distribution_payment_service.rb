class ImportCapitalDistributionPaymentService < ImportServiceBase
  step :read_file
  step Subprocess(ImportCapitalDistributionPayment)
  step :save_results_file
end
