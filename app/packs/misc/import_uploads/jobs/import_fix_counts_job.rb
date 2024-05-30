# This job is called by ImportUploadJob to fix counts after an import is done.
# This is required because the counter_culture updates are deferred during the import process.
# And because specially for remittances, the rollups take an enormous time, as it rolls up all the numbers across all funds for the entity
class ImportFixCountsJob < ApplicationJob
  queue_as :serial
  sidekiq_options retry: 0

  def perform(import_upload_id)
    Chewy.strategy(:sidekiq) do
      import_upload = ImportUpload.find(import_upload_id)
      model_class = import_upload.model_class
      Rails.logger.debug { "Running counter_culture_fix_counts after import for #{model_class}" }
      model_class.counter_culture_fix_counts where: { entity_id: import_upload.entity_id }
    end
  end
end
