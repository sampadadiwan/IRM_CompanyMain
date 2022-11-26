class ImportPostProcess
  include Interactor

  def call
    if context.import_upload.present?
      post_processing(context.import_upload)
    else
      context.fail!(message: "Required inputs not present")
    end
  end

  def post_processing(import_upload)
    result_file_name = "/tmp/import_result_#{import_upload.id}.xlsx"

    if File.exist?(result_file_name)
      import_upload.import_results = File.open(result_file_name, "rb")
      Rails.logger.info "Result file attached for import_upload #{import_upload.id}"
      import_upload.save
      File.delete(result_file_name) if File.exist? result_file_name
    end
  end
end
