class DocumentDownloadJob < ApplicationJob
  queue_as :low
  attr_accessor :tmp_dir

  def perform(folder_id, user_id)
    Chewy.strategy(:sidekiq) do
      user = User.find(user_id)
      folder = Folder.find(folder_id)

      @tmp_dir = "tmp/#{folder_id}"
      FileUtils.mkdir_p @tmp_dir

      File.open("#{@tmp_dir}/download_#{user_id}.zip", "w+") do |zip_file|
        folder_ids = folder.descendant_ids
        folder_ids << folder_id

        Zip::File.open(zip_file.path, Zip::File::CREATE) do |zipfile|
          add_documents(zipfile, user, folder_ids)
        end

        uploaded_document = upload(user, folder, zip_file.path)
        msg = "Zipfile of folder #{folder.name} created. Please download."
        DocumentDownloadNotifier.with(entity_id: folder.entity_id, document: uploaded_document, msg: ).deliver(user)
        send_notification(msg, user_id)
      end

      Rails.logger.debug { "Removing tmp folder #{@tmp_dir}" }
      FileUtils.rm_rf(@tmp_dir)
    end
  end

  def add_documents(zipfile, user, folder_ids)
    document_list = {}
    Pundit.policy_scope(user, Document).where(folder_id: folder_ids).includes(:folder).find_each do |doc|
      doc.file.download do |tmp|
        file_name = get_file_name(doc, tmp)
        zipfile.add(file_name, file_name) if document_list[file_name].nil?
        # This is done to avoid duplicates in the zip file
        document_list[file_name] = "Added"
        Rails.logger.debug { "Added file #{file_name}" }
      end
    end

    Rails.logger.debug "Done with all docs"
  end

  def upload(user, folder, file)
    tmp_folder = user.entity.root_folder.children.where(entity_id: user.entity_id, name: "tmp").first_or_create

    doc = Document.new(name: "Download-#{folder.name}-#{user.full_name}-#{rand(1000)}", folder: tmp_folder, entity: user.entity, orignal: true, user:)
    doc.file = File.open(file, "rb")
    doc.save!
    doc
  end

  def get_file_name(doc, tmp)
    doc_dir = "#{@tmp_dir}#{doc.folder_full_path}"
    file_name = "#{doc_dir}/#{doc.name}#{File.extname(tmp.path)}"
    FileUtils.mkdir_p doc_dir
    FileUtils.move tmp.path, file_name
    file_name
  end
end
