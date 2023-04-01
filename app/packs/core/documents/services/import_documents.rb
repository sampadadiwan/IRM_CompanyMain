class ImportDocuments
  include Interactor

  def call
    if context.import_upload.present? && context.import_file.present?
      begin
        process_rows(context.import_upload)
      rescue StandardError => e
        Rails.logger.debug { "e.message = #{e.message}" }
        Rails.logger.debug e.backtrace
        raise e
      end
    else
      context.fail!(message: "Required inputs not present")
    end
  end

  def process_rows(import_upload)
    unzipped_files = Dir.glob("#{context.unzip_dir}/**/*.*")
    import_upload.total_rows_count = unzipped_files.length

    package = Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: "Import Results") do |sheet|
        # We go thru each directory recursively and try to upload the file
        unzipped_files.each_with_index do |file_path, idx|
          row = [file_path]
          process_row(context.import_upload, context.unzip_dir, file_path, row)
          # add row to results sheet
          sheet.add_row(row)
          # To indicate progress
          import_upload.save if (idx % 10).zero?
        end
      end
    end

    # Save the results file
    File.binwrite("/tmp/import_result_#{import_upload.id}.xlsx", package.to_stream.read)

    post_process(import_upload, context)
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
    import_upload.failed_row_count += 1
  end

  def save_document(import_upload, unzip_dir, file_path)
    Rails.logger.debug { "Processing doc #{file_path}" }

    # We remove the unzip_dir, as we dont want to create the unip dir folders in our app
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

    # Create the document to the last created folder
    doc = Document.new(entity_id: import_upload.entity_id,
                       name: file_name, folder: parent,
                       user_id: import_upload.user_id, send_email: false)

    doc.setup_folder_defaults
    # Attach the actual document on the file system to the document in our app
    doc.file = File.open(file_path, "rb")

    # Allow download of zip
    doc.orignal = true if File.extname(file_path) == ".zip"

    [doc.save, doc.errors.full_messages]
  end

  def post_process(_import_upload, context)
    FileUtils.rm_rf context.unzip_dir
  end
end
