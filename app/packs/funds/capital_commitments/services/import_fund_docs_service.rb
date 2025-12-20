class ImportFundDocsService < ImportServiceBase
  step :read_file
  step Subprocess(ImportFundDocs)
  step :save_results_file

  def read_file(ctx, import_file:, import_upload:, **)
    Rails.logger.debug "Unzipping import fund docs file"
    unzip_dir = "tmp/unzip/#{import_upload.id}"
    ctx[:unzip_dir] = unzip_dir
    # Unzip the contents into the unzip_dir
    unzip(import_file, unzip_dir, import_upload)

    # We replace the import_file with the index.xlsx, so import pre_process can work right
    index_path = find_index_file(unzip_dir)

    unless index_path
      # Check if there is a single directory in the unzip_dir and index.xlsx is inside it
      entries = Dir.glob("#{unzip_dir}/*").select { |f| File.directory?(f) }
      if entries.one?
        nested_dir = entries.first
        index_path = find_index_file(nested_dir)
        Rails.logger.debug { "Found index file in nested directory #{nested_dir}" } if index_path
      end
    end

    if index_path && File.exist?(index_path)
      Rails.logger.debug { "Found index file, proceeding with import in #{File.dirname(index_path)}" }
      import_file = File.open(index_path, "r")
      ctx[:import_file] = import_file
      ctx[:unzip_dir] = File.dirname(index_path)
      super(ctx, import_file:, import_upload:)
    else
      Rails.logger.debug { "index.xlsx not found inside zip file at #{unzip_dir}" }
      ctx[:errors] = "index.xlsx not found inside zip file"
      false
    end
  end

  private

  def find_index_file(dir)
    # Case-insensitive search for index.xlsx
    file_name = Dir.entries(dir).find { |f| f.downcase == "index.xlsx" }
    "#{dir}/#{file_name}" if file_name
  end
end
