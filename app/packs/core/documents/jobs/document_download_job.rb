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
        DocumentDownloadNotification.with(entity_id:, document_id: uploaded_document.id, msg: "Zipfile of folder #{folder.name} created. Please download.").deliver(user)
      end

      Rails.logger.debug { "Removing tmp folder #{@tmp_dir}" }
      FileUtils.rm_rf(@tmp_dir)
    end
  end

  def add_documents(zipfile, user, folder_ids)
    Pundit.policy_scope(user, Document).where(folder_id: folder_ids).includes(:folder).each do |doc|
      doc.file.download do |tmp|
        file_name = get_file_name(doc, tmp)
        zipfile.add(file_name, file_name)
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
