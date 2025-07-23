class DocumentDownloadJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 0
  attr_accessor :tmp_dir

  def perform(folder_id, user_id, document_ids = nil)
    # rubocop:disable Metrics/BlockLength
    Chewy.strategy(:sidekiq) do
      user = User.find(user_id)
      folder = Folder.find(folder_id)
      same_entity = (user.entity_id == folder.entity_id)

      @tmp_dir = "tmp/#{folder_id}"
      FileUtils.mkdir_p @tmp_dir

      begin
        File.open("#{@tmp_dir}/docs_#{Time.zone.now.strftime('%m%d%H%M%S')}.zip", "w+") do |zip_file|
          folder_ids = folder.descendant_ids
          folder_ids << folder_id

          Zip::File.open(zip_file.path, Zip::File::CREATE) do |zipfile|
            if document_ids.present?
              add_documents(zipfile, user, folder_ids:, document_ids:, same_entity:)
            else
              add_documents(zipfile, user, folder_ids:, same_entity:)
            end
          end

          uploaded_document = upload(user, zip_file.path, folder:)
          # set expiry to 1 day
          download_link = "<a href='#{uploaded_document.file.url(expires_in: 60 * 60 * 24)}'><b>Download</b></a>"
          msg = "#{download_link} the ZIP file. A download link has also been sent to your email. Please note that the link will expire in 1 day."
          DocumentDownloadNotifier.with(entity_id: folder.entity_id, document: uploaded_document, msg:).deliver(user)
          send_notification(msg, user_id)
        end
      rescue StandardError => e
        Rails.logger.error { "Error in creating zip file: #{e.message}" }
        send_notification("Error in creating zip file: #{e.message}", user_id, "danger")
        Rails.logger.error { e.backtrace.join("\n") }
        raise e
      ensure
        Rails.logger.debug { "Removing tmp folder #{@tmp_dir}" }
        FileUtils.rm_rf(@tmp_dir)
      end
    end
    # rubocop:enable Metrics/BlockLength
  end

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

    add_docs_to_zip(zipfile, user, docs, document_list, no_check_individual_docs_access)
    Rails.logger.debug "Done with all docs"
  end

  def add_docs_to_zip(zipfile, user, docs, document_list, no_check_individual_docs_access)
    docs.find_each do |doc|
      # You can only download a document if you have access to it
      if no_check_individual_docs_access || Pundit.policy(user, doc).show?
        doc.file.download do |tmp|
          doc_dir, file_name = get_file_name(doc, tmp)

          unless document_list[file_name].nil?
            og_file_name = file_name
            Rails.logger.debug { "File #{og_file_name} already exists" }
            counter = 1
            file_name_no_ext = og_file_name[0...og_file_name.rindex('.')]
            file_name = "#{file_name_no_ext} (#{counter})#{File.extname(og_file_name)}"
            while document_list[file_name].present?
              counter += 1
              file_name = "#{file_name_no_ext} (#{counter})#{File.extname(og_file_name)}"
            end
          end
          make_directory(doc_dir, tmp, file_name)
          zipfile.add(file_name, file_name)
          document_list[file_name] = "Added"
          Rails.logger.debug { "Added file #{file_name}" }
        end
      else
        Rails.logger.debug { "User #{user.email} does not have access to document #{doc.id}" }
      end
    end
  end

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
    doc = Document.new(name:, folder: tmp_folder, entity: user.entity, orignal: true, user:)
    doc.file = File.open(file, "rb")
    doc.save!
    doc
  end

  def get_file_name(doc, tmp)
    doc_dir = "#{@tmp_dir}#{doc.folder_full_path}"
    doc_name = doc.name
    file_name = "#{doc_dir}/#{doc_name.tr('/', '_')}#{File.extname(tmp.path)}"
    [doc_dir, file_name]
  end

  def make_directory(doc_dir, tmp, file_name)
    FileUtils.mkdir_p doc_dir
    FileUtils.move tmp.path, file_name
  end
end
