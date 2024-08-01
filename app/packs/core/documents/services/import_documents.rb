class ImportDocuments < ImportUtil
  step nil, delete: :validate_headers
  step nil, delete: :create_custom_fields

  def save_data(ctx, import_upload:, **)
    unzip_dir = ctx[:unzip_dir]
    unzipped_files = Dir.glob("#{unzip_dir}/**/*.*")
    import_upload.total_rows_count = unzipped_files.length

    package = Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Import Results") do |sheet|
        # We go thru each directory recursively and try to upload the file
        unzipped_files.each_with_index do |file_path, idx|
          row = [file_path]
          process_row(import_upload, unzip_dir, file_path, row)
          # add row to results sheet
          sheet.add_row(row)
          # To indicate progress
          import_upload.save if (idx % 10).zero?
        end
      end
    end

    # Save the results file
    File.binwrite("/tmp/import_result_#{import_upload.id}.xlsx", package.to_stream.read)
  end

  def process_row(import_upload, unzip_dir, file_path, row)
    status, msg = save_document(import_upload, unzip_dir, file_path)
    if status
      import_upload.processed_row_count += 1
    else
      import_upload.failed_row_count += 1
    end
    row << msg
  rescue ActiveRecord::Deadlocked => e
    raise e
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    row << "Error #{e.message}"
    row << e.backtrace
    import_upload.failed_row_count += 1
  end

  def save_document(import_upload, unzip_dir, file_path)
    Rails.logger.debug { "Processing doc #{file_path}" }

    # We remove the unzip_dir, as we dont want to create the unzip dir folders in our app
    folders = file_path.gsub("#{unzip_dir}/", '').split("/")[0..-2]
    file_name = file_path.split("/")[-1]

    # Walk thru the folders and create them in our system
    parent = import_upload.owner
    folders.each do |folder|
      child_folder = parent.children.where(entity_id: import_upload.entity_id, name: folder,
                                           folder_type: "regular").first_or_initialize

      if child_folder.new_record?
        child_folder.download = parent.download
        child_folder.printing = parent.printing
        child_folder.orignal = parent.orignal
        child_folder.save
      end

      parent = child_folder
    end

    # Sometimes we dont get a file but a directory or a special file
    if File.basename(file_path) == "desktop.ini"
      [true, "Skipped"]
    elsif File.directory?(file_path)
      [true, "Directory"]
    else
      # Create the document to the last created folder
      doc = Document.find_or_initialize_by(entity_id: import_upload.entity_id,
                                           name: file_name, folder: parent,
                                           import_upload_id: import_upload.id)

      if doc.new_record?
        save_doc(doc, file_path, import_upload)
      else
        [false, "Document with same name already exists in the folder"]
      end

    end
  end

  def save_doc(doc, file_path, import_upload)
    doc.user_id = import_upload.user_id
    doc.send_email = false
    doc.setup_folder_defaults
    # Attach the actual document on the file system to the document in our app
    raise "#{file_path} does not exist. Check for missing file or extension" unless File.exist?(file_path)

    doc.file = File.open(file_path, "rb")

    # Allow download of zip
    doc.orignal = true if File.extname(file_path) == ".zip"
    [doc.save, doc.errors.full_messages]
  end

  def post_process(ctx, **)
    FileUtils.rm_rf ctx[:unzip_dir]
  end
end
