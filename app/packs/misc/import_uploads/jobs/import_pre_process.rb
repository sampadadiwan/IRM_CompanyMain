class ImportPreProcess
  include Interactor

  def call
    if context.import_upload.present? && context.import_file.present?
      context.headers, context.data = pre_process(context.import_file, context.import_upload)
    else
      context.fail!(message: "Required inputs not present")
    end
  end

  def pre_process(file, import_upload)
    data = Roo::Spreadsheet.open(file.path) # open spreadsheet
    headers = data.row(1) # get header row

    import_upload.status = nil
    import_upload.error_text = nil
    import_upload.failed_row_count = 0
    import_upload.processed_row_count = 0
    import_upload.total_rows_count = data.last_row - 1
    import_upload.save

    [headers, data]
  end
end
