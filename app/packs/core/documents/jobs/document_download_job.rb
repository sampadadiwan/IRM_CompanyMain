class DocumentDownloadJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 0
  attr_accessor :tmp_dir, :missing_files

  # Executes the document download job.
  # Creates a ZIP file containing the requested documents and/or folder contents,
  # uploads it as a temporary document, and notifies the user with a download link.
  #
  # @param folder_id [Integer] The ID of the root folder to download.
  # @param user_id [Integer] The ID of the user requesting the download.
  # @param document_ids [Array<Integer>, nil] Specific document IDs to download; if nil, downloads all in folder.
  def perform(folder_id, user_id, document_ids = nil)
    # rubocop:disable Metrics/BlockLength

    # Create a unique temporary directory for this job execution.
    # Appending a hex suffix prevents collisions between concurrent jobs for the same folder.
    @tmp_dir = "tmp/#{folder_id}_#{SecureRandom.hex(4)}"
    @missing_files = []
    FileUtils.mkdir_p @tmp_dir

    # The outer begin-ensure block guarantees that the @tmp_dir is removed even if
    # record lookups fail or an exception is raised before/inside the Chewy block.
    begin
      Chewy.strategy(:sidekiq) do
        user = User.find(user_id)
        folder = Folder.find(folder_id)
        same_entity = (user.entity_id == folder.entity_id)

        # Ensure Zip64 support is enabled for large files
        Zip.setup do |c|
          c.default_compression = Zlib::DEFAULT_COMPRESSION
          c.write_zip64_support = true
        end

        zip_filename = "#{@tmp_dir}/docs_#{Time.zone.now.strftime('%m%d%H%M%S')}.zip"
        folder_ids = folder.descendant_ids
        folder_ids << folder_id

        Zip::File.open(zip_filename, Zip::File::CREATE) do |zipfile|
          if document_ids.present?
            add_documents(zipfile, user, folder_ids:, document_ids:, same_entity:)
          else
            add_documents(zipfile, user, folder_ids:, same_entity:)
          end
        end

        # After zip creation, upload it as a Document record so it can be served via a secure URL.
        uploaded_document = upload(user, zip_filename, folder:)

        # Prepare notification with a 5-day expiry link for the user.
        download_link = "<a href='#{uploaded_document.file.url(expires_in: 60 * 60 * 24 * 5)}'><b>Download</b></a>"
        msg = "#{download_link} the ZIP file. A download link has also been sent to your email. Please note that the link will expire in 5 days."
        if @missing_files.any?
          msg += "<br/><br/>The following files could not be included because they were missing from storage: <ul><li>#{@missing_files.join('</li><li>')}</li></ul>"
        end
        DocumentDownloadNotifier.with(entity_id: folder.entity_id, document: uploaded_document, msg:).deliver(user)
        send_notification(msg, user_id)
      end
    rescue StandardError => e
      Rails.logger.error { "Error in creating zip file: #{e.message}" }
      send_notification("Error in creating zip file: #{e.message}", user_id, "danger")
      Rails.logger.error { e.backtrace.join("\n") }
      raise e
    ensure
      # Comprehensive cleanup: delete the entire temporary directory and its contents.
      # This reclaims space used by both the individual file downloads and the local zip file.
      if @tmp_dir.present? && Dir.exist?(@tmp_dir)
        Rails.logger.debug { "Removing tmp folder #{@tmp_dir}" }
        FileUtils.rm_rf(@tmp_dir)
      end
    end
    # rubocop:enable Metrics/BlockLength
  end

  # Prepares the list of documents to be added to the ZIP file based on permissions.
  #
  # @param zipfile [Zip::File] The ZIP file object being constructed.
  # @param user [User] The user performing the download.
  # @param folder_ids [Array<Integer>] List of folder IDs to include.
  # @param document_ids [Array<Integer>, nil] Optional list of specific document IDs.
  # @param same_entity [Boolean] Whether the user and folder belong to the same entity.
  def add_documents(zipfile, user, folder_ids:, document_ids: nil, same_entity: false)
    # If the user is a company admin, they can download all documents
    no_check_individual_docs_access = same_entity && user.has_cached_role?(:company_admin)
    document_list = {}
    docs = if no_check_individual_docs_access
             # Still apply policy scope to get the documents the user has access to
             Pundit.policy_scope(user, Document)
           else
             # It may look like we are giving unlimited access to the documents, but the policy will still be applied in the loop below
             Document.all
           end
    docs = docs.where(folder_id: folder_ids).includes(:folder).order(created_at: :asc) if folder_ids.present?
    docs = docs.where(id: document_ids) if document_ids.present?

    # Filter out documents in folders named 'tmp' or 'temp' or their subfolders
    # We use full_path to identify subfolders. Subfolders of 'tmp' will have full_path starting with '/tmp/' or being '/tmp'
    # However, since the root folder name is '/', the full_path of a 'tmp' folder at root is '/tmp'
    # and its subfolder is '/tmp/subfolder'
    docs = docs.joins(:folder).where.not("folders.full_path LIKE '%/tmp/%' OR folders.full_path LIKE '%/temp/%'")

    add_docs_to_zip(zipfile, user, docs, document_list, no_check_individual_docs_access)
    Rails.logger.debug "Done with all docs"
  end

  # Iterates through the provided documents and adds them to the ZIP archive.
  # Respects Pundit policies unless administrative access is granted.
  #
  # @param zipfile [Zip::File] The ZIP file object.
  # @param user [User] The user performing the download.
  # @param docs [ActiveRecord::Relation] The collection of documents to process.
  # @param document_list [Hash] A registry to track added filenames and handle collisions.
  # @param no_check_individual_docs_access [Boolean] If true, skips individual Pundit checks.
  def add_docs_to_zip(zipfile, user, docs, document_list, no_check_individual_docs_access)
    # Batch process documents to optimize memory and database performance
    docs.find_each do |doc|
      # Access Control: Verify user permissions unless bypass is enabled (e.g., Company Admin)
      if no_check_individual_docs_access || Pundit.policy(user, doc).show?
        begin
          # Stream the file from storage to a local temporary file
          doc.file.download do |tmp|
            # Determine the target directory and initial filename within the ZIP structure
            doc_dir, file_name = get_file_name(doc, tmp)

            # Collision Resolution: Handle duplicate filenames by appending a counter
            unless document_list[file_name].nil?
              og_file_name = file_name
              Rails.logger.debug { "File #{og_file_name} already exists" }
              counter = 1
              # Extract name without extension for suffixing
              file_name_no_ext = og_file_name[0...og_file_name.rindex('.')]
              file_name = "#{file_name_no_ext} (#{counter})#{File.extname(og_file_name)}"

              # Increment counter until a unique filename in the current ZIP session is found
              while document_list[file_name].present?
                counter += 1
                file_name = "#{file_name_no_ext} (#{counter})#{File.extname(og_file_name)}"
              end
            end

            # Physically create the directory and place the file in the local workspace (@tmp_dir)
            make_directory(doc_dir, tmp, file_name)

            # Add the local file to the ZIP archive using its virtual path (relative to @tmp_dir)
            # Ensure no leading slash is present in the zip entry name to avoid Zip::EntryNameError
            entry_name = file_name.delete_prefix("#{@tmp_dir}/").delete_prefix("/")
            zipfile.add(entry_name, file_name)

            # Register the filename as used to prevent future collisions in this ZIP
            document_list[file_name] = "Added"
            Rails.logger.debug { "Added file #{file_name}" }
          end
        rescue Shrine::FileNotFound => e
          Rails.logger.error { "File not found for document #{doc.id}: #{e.message}" }
          @missing_files << "#{doc.folder_full_path}/#{doc.name}".delete_prefix("/")
        end
      else
        # Log skipped files for audit/debugging purposes
        Rails.logger.debug { "User #{user.email} does not have access to document #{doc.id}" }
      end
    end
  end

  # Uploads the generated ZIP file back to the system as a Document.
  # Places the file in a 'tmp' folder within the user's entity root.
  #
  # @param user [User] The user who will own the uploaded ZIP.
  # @param file [String] Local path to the ZIP file.
  # @param folder [Folder] The folder context for naming the ZIP file.
  # @return [Document] The created Document record.
  def upload(user, file, folder:)
    # Create a tmp folder if it doesn't exist in the root folder
    tmp_folder = user.entity.root_folder.children.where(entity_id: user.entity_id, name: "tmp").first_or_create
    # Create a unique name for the document
    name = if folder.present?
             "Download-#{folder.name}-#{user.full_name}-#{Time.zone.now.strftime('%m%d%H%M%S')}"
           else
             "Download-#{user.full_name}-#{Time.zone.now.strftime('%m%d%H%M%S')}"
           end

    # Create the document
    doc = Document.new(name:, folder: tmp_folder, entity: user.entity, orignal: true, user:, owner_tag: "Generated")
    doc.file = File.open(file, "rb")
    doc.save!
    doc
  end

  # Calculates the local path and filename for a document within the temporary directory.
  # Replaces slashes in document names to prevent directory traversal issues.
  #
  # @param doc [Document] The document being processed.
  # @param tmp [Tempfile] The temporary file object from ActiveStorage download.
  # @return [Array<String, String>] The directory path and the full file path.
  def get_file_name(doc, tmp)
    doc_dir = "#{@tmp_dir}#{doc.folder_full_path}"
    doc_name = doc.name
    file_name = "#{doc_dir}/#{doc_name.tr('/', '_')}#{File.extname(tmp.path)}"
    [doc_dir, file_name]
  end

  # Creates the necessary directory structure and copies the temporary file to its destination.
  # Using copy instead of move ensures ActiveStorage can clean up its own temp file.
  #
  # @param doc_dir [String] The directory path to create.
  # @param tmp [Tempfile] The source temporary file.
  # @param file_name [String] The destination file path.
  def make_directory(doc_dir, tmp, file_name)
    FileUtils.mkdir_p doc_dir
    # Use copy instead of move.
    # 'move' would prevent the calling block (doc.file.download) from finding the
    # temporary file to delete it after the block finishes, causing a leak in /tmp.
    # Our final ensure block in #perform will clean up this copy in @tmp_dir.
    FileUtils.copy tmp.path, file_name
  end
end
