class ImageService
  def self.pdf_to_image(document, file, folder_path, image_path)
    output_prefix = "#{folder_path}/#{document.id}"

    # Ensure the directory exists
    FileUtils.mkdir_p(folder_path)

    # Convert PDF to PNG
    `pdftoppm -png -r 300 #{file.path} #{output_prefix}`

    # Get list of images
    image_paths = Dir.glob("#{output_prefix}-*.png")
    Rails.logger.debug { "Generated images: #{image_paths.inspect}" }

    # If only one image exists, just copy it
    if image_paths.size == 1
      Rails.logger.warn { "Only one image found, copying it instead of stacking." }
      FileUtils.cp(image_paths.first, image_path)
      return image_path
    end

    # Use ImageMagick to combine images vertically
    `convert #{image_paths.join(' ')} -append #{image_path}`

    Rails.logger.debug { "Saved combined image to #{image_path}" }

    image_path
  end

  def self.encode_image(image_path)
    Rails.logger.debug { "Encoding image #{image_path}" }
    file_extension = File.extname(image_path).delete(".")
    image = Base64.encode64(File.read(image_path))
    "data:image/#{file_extension};base64,#{image}"
  end
end
