class ImportKycDocsService < ImportServiceBase
  step :read_file
  step Subprocess(ImportKycDocs)
  step :save_results_file

  def read_file(ctx, import_file:, import_upload:, **)
    unzip_dir = "tmp/unzip/#{import_upload.id}"
    Rails.logger.debug { "Unzipping import file to #{unzip_dir}" }
    ctx[:unzip_dir] = unzip_dir
    # Unzip the contents into the unzip_dir
    unzip(import_file, unzip_dir, import_upload)
    # We replace the import_file with the index.xlsx, so import pre_process can work right
    if File.exist?("#{unzip_dir}/index.xlsx")
      Rails.logger.debug "Found index.xlsx inside zip file"
      import_file = File.open("#{unzip_dir}/index.xlsx", "r")
      ctx[:import_file] = import_file
      super(ctx, import_file:, import_upload:)
    else
      Rails.logger.debug "index.xlsx not found inside zip file"
      ctx[:errors] = "index.xlsx not found inside zip file"
      false
    end
  end
end
