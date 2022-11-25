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

    case import_upload.import_type
    when "InvestorAccess"
      Rails.logger.info "Importing InvestorAccess Done"
    when "Holding", "Offer", "CapitalCommittment"
      import_upload.import_results = File.open(result_file_name, "rb")
      Rails.logger.info "Importing Holding Done"
    end

    import_upload.save
    File.delete(result_file_name) if File.exist? result_file_name
  end
end
