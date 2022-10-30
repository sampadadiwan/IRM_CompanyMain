class ImportUploadJob < ApplicationJob
  queue_as :default

  def perform(import_upload_id)
    Chewy.strategy(:sidekiq) do
      import_upload = ImportUpload.find(import_upload_id)
      # file = Tempfile.new(["import_#{import_upload.id}", ".xlsx"], binmode: true)
      begin
        # Download the S3 file to tmp
        import_upload.import_file.download do |file|
          case import_upload.import_type
          when "InvestorAccess"
            ImportInvestorAccessService.call(import_file: file, import_upload:)
          when "Investor"
            ImportInvestorService.call(import_file: file, import_upload:)
          when "Holding"
            ImportHoldingService.call(import_file: file, import_upload:)
          when "Offer"
            ImportOfferService.call(import_file: file, import_upload:)
          else
            err_msg = "Bad import_type #{import_upload.import_type} : #{import_upload.id}"
            Rails.logger.error err_msg
            raise err_msg
          end
        end
      rescue StandardError => e
        import_upload.status = e.message
        import_upload.error_text = e.backtrace
        Rails.logger.error e.backtrace
      end

      import_upload.save
    end
  end
end
