# Upload wrapper for ImportDerivativeEvent (import_type "DerivativeEvent")
class ImportDerivativeEventService < ImportServiceBase
  step :read_file
  step Subprocess(ImportDerivativeEvent)
  step :save_results_file
end
