module DocumentGeneratorBase
  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif].freeze
  def convert(template, context, file_name, to_pdf: true)
    # Mail Merge
    template.render_to_file File.expand_path("#{file_name}.docx"), context
    if to_pdf
      # Convert to PDF
      Libreconv.convert("#{file_name}.docx", "#{file_name}.pdf")
    end
  end

  def create_working_dir(model)
    @working_dir = working_dir_path(model)
    FileUtils.mkdir_p @working_dir
  end

  def working_dir_path(model)
    "tmp/#{model.class.name}/#{rand(1_000_000)}/#{model.id}"
  end

  def generated_file_name(model)
    "#{@working_dir}/#{model.class.name}-#{model.id}"
  end

  def cleanup
    FileUtils.rm_rf(@working_dir) if @working_dir
  end

  def add_image(context, field_name, image)
    if image
      file = image.download
      stored_file_path = "#{@working_dir}/#{File.basename(file.path)}"

      FileUtils.mv(file.path, stored_file_path)

      context.store "image:#{field_name}", stored_file_path
      stored_file_path
    end
  end

  def add_header_footers(model, spa_path, additional_headers = nil, additional_footers = nil, template_name = nil)
    header_footer_download_path = []

    combined_pdf = CombinePDF.new
    generate_headers(model, additional_headers, combined_pdf, header_footer_download_path, template_name)

    # Combine the SPA
    combined_pdf << CombinePDF.load("#{spa_path}.pdf")

    generate_footers(model, additional_footers, combined_pdf, header_footer_download_path, template_name)

    # Overwrite the orig SPA with the one with header and footer
    combined_pdf.save("#{spa_path}.pdf")

    header_footer_download_path.each do |file_path|
      FileUtils.rm_f(file_path)
    end
  end

  def generate_headers(model, additional_headers, combined_pdf, header_footer_download_path, template_name = nil)
    # Get the headers
    headers = model.documents.where(name: ["Header", "Stamp Paper", "#{template_name} Header", "#{template_name} Stamp Paper"])
    headers += additional_headers if additional_headers.present?
    header_count = headers.count
    Rails.logger.debug { "headers are #{headers.collect(&:name)}" }

    # Combine the headers
    if header_count.positive?
      headers.each do |header|
        file = header.file.download
        header_footer_download_path << file.path
        combined_pdf << CombinePDF.load(file.path)
      rescue StandardError => e
        msg = "Error adding Header: #{header.name}: #{e.message}"
        Rails.logger.error { msg }
        raise msg
      end
    end
  end

  def generate_footers(model, additional_footers, combined_pdf, header_footer_download_path, template_name = nil)
    # Get the footers
    footers = model.documents.where(name: ["Footer", "#{template_name} Footer", "#{template_name} Signature"]).to_a
    footers += additional_footers if additional_footers.present?
    Rails.logger.debug { "footers are #{footers.collect(&:name)}" }
    # Combine the footers
    if footers.length.positive?
      footers.each do |footer|
        file = footer.file.download
        # Sometimes the files are images, so we need to convert to pdf
        if IMAGE_EXTENSIONS.include?(File.extname(file.path))
          Libreconv.convert(file.path, "#{file.path}.pdf")
          file_path = "#{file.path}.pdf"
        else
          file_path = file.path
        end
        Rails.logger.debug { "Adding footer #{file_path}" }
        header_footer_download_path << file_path
        combined_pdf << CombinePDF.load(file_path)
      rescue StandardError => e
        msg = "Error adding Footer: #{footer.name}: #{e.message}"
        Rails.logger.error { msg }
        raise msg
      end
    end
  end

  def send_notification(message, user_id, level = "success")
    UserAlert.new(user_id:, message:, level:).broadcast
  end

  def upload(doc_template, model, start_date = nil, end_date = nil, folder = nil, generated_document_name = nil, file_extension: "pdf")
    file_name = "#{generated_file_name(model)}.#{file_extension}"
    Rails.logger.debug { "Uploading generated file #{file_name} to #{model} " }

    # Clone some attributes of the template
    generated_document = Document.new(doc_template.attributes.slice("entity_id", "name", "orignal", "download", "printing", "user_id", "display_on_page", "force_esign_order"))

    # Get the name of the doc we are generating
    generated_document.name = generated_document_name
    generated_document.name ||= if start_date && end_date
                                  "#{doc_template.name} #{start_date} to #{end_date} - #{model}"
                                else
                                  "#{doc_template.name} - #{model}"
                                end

    # Destroy existing docs with the same name for the model
    # except for signed ones
    model.documents.where(name: generated_document.name).where.not(owner_tag: "signed").find_each(&:destroy)

    # Upload the generated file
    generated_document.file = File.open(file_name, "rb")
    generated_document.from_template = doc_template
    generated_document.owner = model
    generated_document.owner_tag = "Generated"
    generated_document.send_email = false
    generated_document.folder = folder if folder

    # Add the e-signatures and stamp papers if available
    generated_document.e_signatures = doc_template.e_signatures_for(model) || []
    generated_document.e_signatures.each do |esign|
      esign.document = generated_document
      esign.entity = model.entity
    end
    generated_document.stamp_papers = doc_template.stamp_papers_for(model) || []

    generated_document.save!
  end
end
