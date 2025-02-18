class ImportUploadJob < ApplicationJob
  queue_as :serial
  sidekiq_options retry: 0

  def perform(import_upload_id)
    Chewy.strategy(:sidekiq) do
      import_upload = ImportUpload.find(import_upload_id)
      begin
        # Download the S3 file to tmp
        import_upload.import_file.download do |file|
          "Import#{import_upload.import_type}Service".constantize.call(import_file: file, import_upload:)
        end
      rescue ActiveRecord::Deadlocked => e
        raise e
      rescue StandardError => e
        import_upload.status = e.message
        import_upload.error_text = e.backtrace
        Rails.logger.error e.backtrace
      end

      import_upload.save

      send_notification("Import of #{import_upload.name} is complete", import_upload.user_id)
    end
  end
end
