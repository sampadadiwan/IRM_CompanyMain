class ImportUnzipFile
  include Interactor

  def call
    if context.import_upload.present? && context.import_file.present?
      context.unzip_dir = "tmp/unzip/#{context.import_upload.id}"
      # Unzip the contents into the unzip_dir
      unzip(context.import_file, context.unzip_dir, context.import_upload)
      # We replace the import_file with the index.xlsx, so import pre_process can work right
      context.import_file = File.open("#{context.unzip_dir}/index.xlsx", "r") if File.exist?("#{context.unzip_dir}/index.xlsx")
    else
      context.fail!(message: "Required inputs not present")
    end
  end

  def unzip(file, unzip_dir, _import_upload)
    FileUtils.mkdir_p unzip_dir
    dest_file = "#{unzip_dir}/#{File.basename(file.path)}"
    FileUtils.mv(file.path, dest_file)

    # Zip::File.open(dest_file) do |zip_file|
    #   # Handle entries one by one
    #   zip_file.each do |entry|
    #     Rails.logger.debug { "Extracting #{entry.name}" }
    #     # Extract to file or directory based on name in the archive
    #     entry.extract "#{unzip_dir}/#{entry.name}"
    #   end
    # end

    # Some files were not getting uzipped by ruby zip, so we use the system unzip
    `unzip -o #{dest_file} -d #{unzip_dir}`
  rescue StandardError => e
    Rails.logger.debug e.message
    raise e
  end

  # get header row without the mandatory *
  def get_headers(headers)
    headers.each { |x| x.delete!("*") }.each(&:strip!)
  end
end
