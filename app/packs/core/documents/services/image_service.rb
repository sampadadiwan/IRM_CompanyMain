class ImageService
  def self.pdf_to_image(document, file, folder_path, image_path)
    magick = MiniMagick::Image.open(file.path)
    image_paths = []
    # Iterate through each page in the document
    magick.pages.each_with_index do |image, index|
      # Apply desired transformations
      image.format "png"
      image.flatten
      image.background "white"
      # Set the density (resolution) for all pages
      image.density 900

      # Define a unique path for each output image
      output_path = "#{folder_path}/#{document.id}_#{index + 1}.png"
      image_paths << output_path
      # Write the transformed image to the output path
      image.write(output_path)

      Rails.logger.debug { "Saved page #{index + 1} to #{output_path}" }
    end

    # Use 'append' with vertical stacking to generate the combined image
    MiniMagick::Tool::Convert.new do |convert|
      image_paths.each do |img|
        convert << img
      end
      convert.append # Append vertically
      convert << image_path
    end
    image_path
  end

  def self.encode_image(image_path)
    Rails.logger.debug { "Encoding image #{image_path}" }
    file_extension = File.extname(image_path).delete(".")
    image = Base64.encode64(File.read(image_path))
    "data:image/#{file_extension};base64,#{image}"
  end
end
