class ImportCapitalRemittancePaymentService < ImportServiceBase
  step :read_file
  step Subprocess(ImportCapitalRemittancePayment)
  step :save_results_file
end
