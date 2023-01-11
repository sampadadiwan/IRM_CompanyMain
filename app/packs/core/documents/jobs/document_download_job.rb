class DocumentDownloadJob < ApplicationJob
  queue_as :low

  def perform(folder_id, user_id)
    user = User.find(user_id)
    folder = Folder.find(folder_id)

    File.open("/tmp/example.zip", "w+") do |zip_file|
      folder_ids = folder.descendant_ids
      folder_ids << folder_id

      Zip::File.open(zip_file.path, Zip::File::CREATE) do |zipfile|
        Pundit.policy_scope(user, Document).where(folder_id: folder_ids).includes(:folder).each do |doc|
          doc.file.download do |tmp|
            file_name = get_file_name(folder_id, doc, tmp)
            zipfile.add("#{doc.folder_full_path[1..]}/#{doc.name}", file_name)
            Rails.logger.debug { "Added file #{file_name}" }
          end
        end

        Rails.logger.debug "Done with all docs"
      end

      Rails.logger.debug { "Removing tmp folder tmp/#{folder_id}" }
      FileUtils.rm_rf("tmp/#{folder_id}")
      Rails.logger.debug { "zip_file.path = #{zip_file.path}" }
    end

    # zip_data = File.read("/tmp/example.zip")
    # zip_data
  end

  def get_file_name(folder_id, doc, tmp)
    tmp_dir = "tmp/#{folder_id}#{doc.folder_full_path}"
    file_name = "#{tmp_dir}/#{doc.name}"
    FileUtils.mkdir_p tmp_dir
    FileUtils.move tmp, file_name
    file_name
  end
end
