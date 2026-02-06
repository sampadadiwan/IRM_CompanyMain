# frozen_string_literal: true

class ImportTaskService < ImportServiceBase
  step :read_file
  step Subprocess(ImportTask)
  step :save_results_file
end
