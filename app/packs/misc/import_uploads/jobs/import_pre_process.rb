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
    data = Roo::Spreadsheet.open(file.path).sheet(0) # open spreadsheet
    headers = get_headers(data.row(1)) # data.row(1).each{|x| x.gsub!("*", "")}.each{|x| x.strip!}
    Rails.logger.debug { "## headers = #{headers}" }
    import_upload.status = nil
    import_upload.error_text = nil
    import_upload.failed_row_count = 0
    import_upload.processed_row_count = 0
    import_upload.total_rows_count = data.last_row - 1
    import_upload.save

    [headers, data]
  rescue StandardError => e
    Rails.logger.debug e.message
    raise e
  end

  # get header row without the mandatory *
  def get_headers(headers)
    # The headers are transformed by strip, squeeze and titleize and then stripped of *
    ret_headers = headers.each { |x| x.delete!("*") }.map { |h| h&.downcase&.strip&.squeeze(" ")&.titleize }
    Rails.logger.debug { "ret_headers = #{ret_headers}" }
    ret_headers
  end
end
