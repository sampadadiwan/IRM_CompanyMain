class ImportDocumentsService < ImportServiceBase
  step :read_file
  step Subprocess(ImportDocuments)
  step :save_results_file

  def read_file(ctx, import_file:, import_upload:, **)
    unzip_dir = "tmp/unzip/#{import_upload.id}"
    ctx[:unzip_dir] = unzip_dir
    # Unzip the contents into the unzip_dir
    unzip(import_file, unzip_dir, import_upload)
    # We replace the import_file with the index.xlsx, so import pre_process can work right
    ctx[:import_file] = File.open("#{unzip_dir}/index.xlsx", "r") if File.exist?("#{unzip_dir}/index.xlsx")
    true
  end
end
