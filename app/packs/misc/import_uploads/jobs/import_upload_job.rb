class ImportUploadJob < ApplicationJob
  queue_as :serial
  sidekiq_options retry: 0

  def perform(import_upload_id)
    Chewy.strategy(:sidekiq) do
      import_upload = ImportUpload.find(import_upload_id)
      begin
        # Download the S3 file to tmp
        import_upload.import_file.download do |file|
          result = "Import#{import_upload.import_type}Service".constantize.wtf?(import_file: file, import_upload:)
          if result.success?
            import_upload.status = "Completed"
          else
            import_upload.status = "Failed"
            import_upload.error_text = result[:errors]
          end
        end
      rescue ActiveRecord::Deadlocked => e
        raise e
      rescue StandardError => e
        import_upload.status = e.message
        import_upload.error_text = e.backtrace
        Rails.logger.error e.backtrace
      end

      import_upload.save
      if import_upload.failed_row_count.positive? || import_upload.status == "Failed"
        msg = "Import of #{import_upload.name} failed with #{import_upload.failed_row_count}, #{import_upload.error_text} errors"
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
