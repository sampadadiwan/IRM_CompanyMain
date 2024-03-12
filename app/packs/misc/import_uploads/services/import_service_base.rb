class ImportServiceBase < Trailblazer::Operation
  def read_file(ctx, import_file:, import_upload:, **)
    data = Roo::Spreadsheet.open(import_file.path).sheet(0) # open spreadsheet
    headers = get_headers(data.row(1)) # data.row(1).each{|x| x.gsub!("*", "")}.each{|x| x.strip!}
    Rails.logger.debug { "## headers = #{headers}" }
    import_upload.status = nil
    import_upload.error_text = nil
    import_upload.failed_row_count = 0
    import_upload.processed_row_count = 0
    import_upload.total_rows_count = data.last_row - 1
    import_upload.save

    ctx[:headers] = headers
    ctx[:data] = data
    true
  rescue StandardError => e
    Rails.logger.debug e.message
    raise e
  end

  def save_results_file(_ctx, import_upload:, **)
    result_file_name = "/tmp/import_result_#{import_upload.id}.xlsx"
    result = true
    if File.exist?(result_file_name)
      import_upload.import_results = File.open(result_file_name, "rb")
      Rails.logger.info "Result file attached for import_upload #{import_upload.id}"
      result = import_upload.save
      FileUtils.rm_f(result_file_name)
    end
    result
  end

  # get header row without the mandatory *
  def get_headers(headers)
    # The headers are transformed by strip, squeeze and titleize and then stripped of *
    ret_headers = headers.each { |x| x&.delete!("*") }.map { |h| h&.downcase&.strip&.squeeze(" ")&.titleize }
    Rails.logger.debug { "ret_headers = #{ret_headers}" }
    ret_headers
  end

  def unzip(file, unzip_dir, _import_upload)
    FileUtils.mkdir_p unzip_dir
    dest_file = "#{unzip_dir}/#{File.basename(file.path)}"
    FileUtils.mv(file.path, dest_file)

    # Some files were not getting uzipped by ruby zip, so we use the system unzip
    `unzip -o #{dest_file} -d #{unzip_dir}`
  rescue StandardError => e
    Rails.logger.debug e.message
    raise e
  end
end
