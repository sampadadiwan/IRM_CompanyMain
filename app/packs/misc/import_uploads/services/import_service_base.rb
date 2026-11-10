class ImportServiceBase < Trailblazer::Operation
  def read_file(ctx, import_file:, import_upload:, **)
    data = Roo::Spreadsheet.open(import_file.path).sheet(0) # open spreadsheet
    first_row = data.row(1)
    raise("The first sheet is blank or the first row is empty.") if first_row.compact.empty? # `compact` removes nils, so empty array means no data

    headers = get_headers(first_row) # data.row(1).each{|x| x.gsub!("*", "")}.each{|x| x.strip!}
    Rails.logger.debug { "## headers = #{headers}" }
    import_upload.status = nil
    import_upload.error_text = nil
    import_upload.failed_row_count = 0
    import_upload.processed_row_count = 0
    # A re-run starts with no remembered failures (row_errors, P1)
    import_upload.row_errors = nil
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
    # Fold unicode blanks (eg non-breaking spaces from pasted content) to plain
    # spaces first - String#strip leaves them behind and the header match then fails
    ret_headers = headers.compact.each { |x| x&.delete!("*") }.map { |h| h&.to_s&.gsub(/[[:blank:]]/, " ")&.downcase&.strip&.squeeze(" ")&.titleize }
    Rails.logger.debug { "ret_headers = #{ret_headers}" }
    ret_headers
  end

  def unzip(file, unzip_dir, _import_upload)
    FileUtils.mkdir_p unzip_dir

    # Unzip straight from the downloaded temp file. It must NOT be moved into unzip_dir: the doc
    # imports turn every file in unzip_dir into a Document, so the zip itself (shrine<...>.zip)
    # used to be imported too and showed up in LP document lists. The original zip is already
    # kept on the ImportUpload (import_file) as the audit trail.
    # Some files were not getting uzipped by ruby zip, so we use the system unzip
    # Array form bypasses the shell so paths cannot be interpreted as shell syntax.
    # nil means the binary is missing - fail loudly (into the rescue below) like the old backticks did
    raise Errno::ENOENT, "unzip" if system("unzip", "-o", file.path, "-d", unzip_dir).nil?

    # H8 (OWASP 2026-11) — Info-ZIP unzip restores symlinks stored in the zip, and the doc imports open every
    # file they find. A link to /…/.env.production.in would be imported as a Document. Remove links that lead
    # outside the folder (or nowhere); links inside it are harmless and stay.
    remove_escaping_symlinks(unzip_dir)
  rescue StandardError => e
    Rails.logger.debug e.message
    raise e
  end

  # H8 — delete every symlink under dir whose target is missing or outside dir
  # @param dir [String] the unzipped upload folder
  def remove_escaping_symlinks(dir)
    base = File.realpath(dir)
    # FNM_DOTMATCH: hidden entries too. Ruby's ** does not descend into symlinked folders, but lists the link itself
    Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH).each do |entry|
      next unless File.symlink?(entry)

      target = begin
        File.realpath(entry)
      rescue Errno::ENOENT, Errno::ELOOP
        nil # dangling or looping: nothing legitimate to import
      end
      next if target&.start_with?(base + File::SEPARATOR)

      Rails.logger.warn("[import] removed symlink leading outside the upload folder: #{entry.delete_prefix("#{dir}/")}")
      File.delete(entry)
    end
  end
end
