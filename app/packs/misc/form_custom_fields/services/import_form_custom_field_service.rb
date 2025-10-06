class ImportFormCustomFieldService < ImportServiceBase
  step :read_file
  step Subprocess(ImportFormCustomField)
  step :save_results_file
end
