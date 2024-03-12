class ImportOfferService < ImportServiceBase
  step :read_file
  step Subprocess(ImportOffer)
  step :save_results_file
end
