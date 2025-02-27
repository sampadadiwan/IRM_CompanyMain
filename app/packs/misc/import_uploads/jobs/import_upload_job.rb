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
      if import_upload.failed_row_count.positive?
        msg = "Import of #{import_upload.name} failed with #{import_upload.failed_row_count} errors"
        level = "danger"
      else
        msg = "Import of #{import_upload.name} is complete"
        level = "success"
      end
      Rails.logger.error msg
      send_notification(msg, import_upload.user_id, level)
    end
  end
end
