class ImportFormCustomFieldService < ImportServiceBase
  step :read_file
  step Subprocess(ImportFormCustomFields)
  step :save_results_file
end
