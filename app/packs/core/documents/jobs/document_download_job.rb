class DocumentDownloadJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 0
  attr_accessor :tmp_dir, :missing_files, :skipped_files

  # Executes the document download job.
  # Creates a ZIP file containing the requested documents and/or folder contents,
  # uploads it as a temporary document, and notifies the user with a download link.
  #
  # @param folder_id [Integer] The ID of the root folder to download.
  # @param user_id [Integer] The ID of the user requesting the download.
  # @param document_ids [Array<Integer>, nil] Specific document IDs to download; if nil, downloads all in folder.
  def perform(folder_id, user_id, entity_id: nil, document_ids: nil)
    # Create a unique temporary directory for this job execution.
    # Appending a hex suffix prevents collisions between concurrent jobs for the same folder.
    @tmp_dir = "tmp/#{folder_id}_#{SecureRandom.hex(4)}"
    @missing_files = []
    @skipped_files = []
    FileUtils.mkdir_p @tmp_dir

    # The outer begin-ensure block guarantees that the @tmp_dir is removed even if
    # record lookups fail or an exception is raised before/inside the Chewy block.
    begin
      Chewy.strategy(:sidekiq) do
        user = User.find(user_id)
        folder = Folder.find(folder_id)
        same_entity = (user.entity_id == folder.entity_id)

        # Ensure Zip64 support is enabled for large files
        # We also set the temporary directory to our @tmp_dir to avoid filling up /tmp
        Zip.setup do |c|
          c.default_compression = Zlib::DEFAULT_COMPRESSION
          c.write_zip64_support = true
          c.unicode_names = true
        end

        # This setting is sometimes needed outside Zip.setup for some versions of rubyzip
        Zip.unicode_names = true
        # Ensure RubyZip uses our custom temporary directory instead of the system /tmp
        # Zip.options[:temp_file_base_directory] = @tmp_dir

        zip_filename = "#{@tmp_dir}/docs_#{Time.zone.now.strftime('%m%d%H%M%S')}.zip"
        folder_ids = folder.descendant_ids
        folder_ids << folder_id

        Zip::File.open(zip_filename, Zip::File::CREATE) do |zipfile|
          add_documents(zipfile, user, folder_ids:, entity_id:, document_ids:, same_entity:)
        end

        # After zip creation, upload it as a Document record so it can be served via a secure URL.
        uploaded_document = upload(user, zip_filename, folder:)

        # Prepare notification with a 5-day expiry link for the user.
        download_link = "<a href='#{uploaded_document.file.url(expires_in: 60 * 60 * 24 * 5)}'><b>Download</b></a>"
        msg = "#{download_link} the ZIP file. A download link has also been sent to your email. Please note that the link will expire in 5 days."
        msg += "<br/><br/>The following files could not be included because they were missing from storage: <ul><li>#{@missing_files.join('</li><li>')}</li></ul>" if @missing_files.any?
        msg += "<br/><br/>The following files were skipped due to errors: <ul><li>#{@skipped_files.join('</li><li>')}</li></ul>" if @skipped_files.any?
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
  end

  # Prepares the list of documents to be added to the ZIP file based on permissions.
  #
  # @param zipfile [Zip::File] The ZIP file object being constructed.
  # @param user [User] The user performing the download.
  # @param folder_ids [Array<Integer>] List of folder IDs to include.
  # @param document_ids [Array<Integer>, nil] Optional list of specific document IDs.
  # @param same_entity [Boolean] Whether the user and folder belong to the same entity.
  def add_documents(zipfile, user, folder_ids:, entity_id: nil, document_ids: nil, same_entity: false)
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
    if entity_id.present?
      Rails.logger.debug { "Downloading all documents for entity #{entity_id}" }
      # Download everything for the entity - they are leaving the platform
      docs = docs.where(entity_id: entity_id).includes(:folder)
    elsif folder_ids.present?
      Rails.logger.debug { "Downloading documents in folders: #{folder_ids.join(', ')}" }
      docs = docs.where(folder_id: folder_ids).includes(:folder).order(created_at: :asc)
    end

    docs = docs.where(id: document_ids) if document_ids.present?

    # Filter out documents in folders named 'tmp' or 'temp' or their subfolders
    # We use full_path to identify subfolders.
    # Paths starting with /tmp/ or /temp/ or being exactly /tmp or /temp
    # Also handles paths like /some/path/tmp/ or /some/path/tmp
    docs = docs.joins(:folder).where.not("folders.full_path = '/tmp' OR folders.full_path LIKE '/tmp/%' OR folders.full_path LIKE '%/tmp/%' OR folders.full_path LIKE '%/tmp' OR folders.full_path = '/temp' OR folders.full_path LIKE '/temp/%' OR folders.full_path LIKE '%/temp/%' OR folders.full_path LIKE '%/temp'")

    add_docs_to_zip(zipfile, user, docs, document_list, no_check_individual_docs_access)
    Rails.logger.debug "Done with all docs"
    send_notification("Completed adding documents to ZIP. Compressing.... Will take time.", user.id, "info")
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
    docs.find_each.with_index(1) do |doc, index|
      # Progress Notification: Notify user every 1000 files
      send_notification("Added #{index} files to ZIP...", user.id, "info") if (index % 1000).zero?

      # Access Control: Verify user permissions unless bypass is enabled (e.g., Company Admin)
      unless no_check_individual_docs_access || Pundit.policy(user, doc).show?
        Rails.logger.debug { "User #{user.email} does not have access to document #{doc.id}" }
        next
      end

      begin
        # Define the entry name within the ZIP (relative path)
        # We replace slashes in document names to prevent directory traversal issues.
        # We use doc.name and append extension from metadata
        max_name_length = 200
        extension = ".#{doc.uploaded_file_extension}"
        # Windows illegal characters: < > : " / \ | ? *
        # We replace them with underscores to ensure compatibility.
        doc_name = doc.name.tr('<>:"/\\|?*', '_').slice(0, max_name_length)
        # ZipEntry names must not start with a slash.
        # We also ensure the folder path is sanitized for Windows
        safe_folder_path = doc.folder_full_path.tr('<>:"\\|?*', '_').sub(%r{^/+}, '')
        entry_name = safe_folder_path.present? ? "#{safe_folder_path}/#{doc_name}#{extension}" : "#{doc_name}#{extension}"

        # Collision Resolution: Handle duplicate filenames in the ZIP by appending a counter
        unless document_list[entry_name].nil?
          og_entry_name = entry_name
          Rails.logger.debug { "ZIP entry #{og_entry_name} already exists" }
          counter = 1
          ext = File.extname(og_entry_name)
          base = og_entry_name.delete_suffix(ext)

          entry_name = "#{base} (#{counter})#{ext}"
          while document_list[entry_name].present?
            counter += 1
            entry_name = "#{base} (#{counter})#{ext}"
          end
        end

        # Stream the file from storage directly into the ZIP archive to save disk space
        zipfile.get_output_stream(entry_name) do |os|
          # We use to_io to get the stream and ensure it is closed after copying
          io = doc.file.to_io
          begin
            IO.copy_stream(io, os)
          ensure
            io.close if io.respond_to?(:close)
          end
        end

        # Register the entry name as used to prevent future collisions in this ZIP
        document_list[entry_name] = "Added"
        Rails.logger.debug { "Added file #{entry_name} to zip" }
      rescue Shrine::FileNotFound => e
        Rails.logger.error { "File not found for document #{doc.id}: #{e.message}" }
        @missing_files << "#{doc.folder_full_path}/#{doc.name}".delete_prefix("/")
      rescue StandardError => e
        Rails.logger.error { "Error adding document #{doc.id} to zip: #{e.message}" }
        @skipped_files << "#{doc.folder_full_path}/#{doc.name} (Error: #{e.message})".delete_prefix("/")
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
    # Explicitly opening the file as a Ruby File object and assigning it.
    # We use a standard file assignment to satisfy Shrine's integration.
    # Note: Shrine's S3 storage might still trigger a deprecation warning internally
    # if it uses upload_stream for files it doesn't recognize as disk files,
    # but providing a real File object is the best practice.
    File.open(file, "rb") do |f|
      doc.file = f
      doc.save!
    end

    send_notification("Uploaded ZIP file as document #{doc.id}", user.id, "info")
    doc
  end
end
