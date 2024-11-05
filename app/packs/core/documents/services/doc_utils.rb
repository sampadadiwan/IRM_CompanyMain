class DocUtils
  def self.convert_file_to_image(ctx, document:, **)
    folder_path = "tmp/#{document.owner.class.name}/#{document.id}"
    # make the directory if it does not exist
    FileUtils.mkdir_p(folder_path) unless File.directory?(folder_path)
    # setup the image path
    image_path = "#{folder_path}/#{document.id}.png"
    ctx[:image_path] = image_path
    ctx[:folder_path] = folder_path

    if document.mime_type_includes?('pdf')
      # convert pdf to image
      document.file.download do |file|
        ImageService.pdf_to_image(document, file, folder_path, image_path)
      end
      true
    elsif document.mime_type_includes?('doc')
      # convert doc to image
    elsif document.mime_type_includes?('image')
      # Copy the file to the image_path
      document.file.download do |file|
        FileUtils.cp(file.path, image_path)
      end
      Rails.logger.debug "File is already an image"
      true
    else
      # raise error
      raise "Cannot conver to image"
    end
  end
end
