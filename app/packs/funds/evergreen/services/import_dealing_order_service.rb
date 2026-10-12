class ImportDealingOrderService < ImportServiceBase
  step :read_file
  step Subprocess(ImportDealingOrder)
  step :save_results_file
end
