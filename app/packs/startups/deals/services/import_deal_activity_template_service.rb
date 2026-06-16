class ImportDealActivityTemplateService < ImportServiceBase
  step :read_file
  step Subprocess(ImportDealActivityTemplate)
  step :save_results_file
end
