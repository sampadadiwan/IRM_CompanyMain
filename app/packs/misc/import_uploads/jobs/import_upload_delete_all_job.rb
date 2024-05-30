# This job is called by ImportUploadController to delete all data after an import is done.
class ImportUploadDeleteAllJob < ApplicationJob
  queue_as :low

  def perform(import_upload_id, user_id)
    user = User.find(user_id)
    status = "All imported data deleted by #{user.email}"
    Chewy.strategy(:sidekiq) do
      Audited.audit_class.as_user(user) do
        import_upload = ImportUpload.find(import_upload_id)
        import_upload.imported_data.each(&:destroy)
        import_upload.update(status:, processed_row_count: 0, error_text: nil)
      end
      send_notification(status, user_id)
    end
  end
end
