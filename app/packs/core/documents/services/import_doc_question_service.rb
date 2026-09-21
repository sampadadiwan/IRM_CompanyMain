class ImportDocQuestionService < ImportServiceBase
  step :read_file
  step Subprocess(ImportDocQuestion)
  step :save_results_file
end
