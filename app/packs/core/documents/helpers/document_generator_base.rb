module DocumentGeneratorBase
  def get_odt_file(file_path)
    Rails.logger.debug { "Converting #{file_path} to odt" }
    system("libreoffice --headless --convert-to odt #{file_path} --outdir #{@working_dir}")
    "#{@working_dir}/#{File.basename(file_path, '.*')}.odt"
  end

  def create_working_dir(offer)
    @working_dir = working_dir_path(offer)
    FileUtils.mkdir_p @working_dir
  end

  def cleanup
    FileUtils.rm_rf(@working_dir)
  end

  def add_image(report, field_name, image)
    if image
      file = image.download
      stored_file_path = "#{@working_dir}/#{File.basename(file.path)}"

      FileUtils.mv(file.path, stored_file_path)

      report.add_image field_name.to_sym, stored_file_path
      stored_file_path
    end
  end

  def add_header_footers(model, spa_path, additional_headers = nil, additional_footers = nil)
    header_footer_download_path = []

    combined_pdf = CombinePDF.new
    generate_headers(model, additional_headers, combined_pdf, header_footer_download_path)

    # Combine the SPA
    combined_pdf << CombinePDF.load(spa_path)

    generate_footers(model, additional_footers, combined_pdf, header_footer_download_path)

    # Overwrite the orig SPA with the one with header and footer
    combined_pdf.save(spa_path)

    header_footer_download_path.each do |file_path|
      FileUtils.rm_f(file_path)
    end
  end

  def generate_headers(model, additional_headers, combined_pdf, header_footer_download_path)
    # Get the headers
    headers = model.documents.where(name: ["Header", "Stamp Paper"])
    headers += additional_headers if additional_headers.present?
    header_count = headers.count
    Rails.logger.debug { "headers are #{headers.collect(&:name)}" }

    # Combine the headers
    if header_count.positive?
      headers.each do |header|
        file = header.file.download
        header_footer_download_path << file.path
        combined_pdf << CombinePDF.load(file.path)
      end
    end
  end

  def generate_footers(model, additional_footers, combined_pdf, header_footer_download_path)
    # Get the footers
    footers = model.documents.where(name: %w[Footer Signature]).to_a
    footers += additional_footers if additional_footers.present?
    Rails.logger.debug { "footers are #{footers.collect(&:name)}" }
    # Combine the footers
    if footers.length.positive?
      footers.each do |footer|
        file = footer.file.download
        header_footer_download_path << file.path
        combined_pdf << CombinePDF.load(file.path)
      end
    end
  end
end
