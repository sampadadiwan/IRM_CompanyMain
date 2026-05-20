require "hexapdf"

module DocumentGeneratorBase
  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif].freeze

  def convert(template, context, file_name, to_pdf: true)
    # Mail Merge
    file_path = File.expand_path("#{file_name}.docx")
    Rails.logger.debug { "#{self.class} Generating document at #{file_path}" }
    template.render_to_file(file_path, context)
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

    combined_pdf = HexaPDF::Document.new
    generate_headers(model, additional_headers, combined_pdf, header_footer_download_path, template_name)

    # Combine the SPA PDF
    append_pdf(combined_pdf, "#{spa_path}.pdf")

    generate_footers(model, additional_footers, combined_pdf, header_footer_download_path, template_name)

    # Save final PDF
    # Write to a temp file first to avoid overwriting the source file (spa_path.pdf)
    # while it is still being read by HexaPDF (lazy loading).
    temp_output_path = "#{spa_path}_temp.pdf"
    combined_pdf.write(temp_output_path, optimize: true)
    FileUtils.mv(temp_output_path, "#{spa_path}.pdf")
  ensure
    header_footer_download_path.each { |file_path| FileUtils.rm_f(file_path) }
  end

  def generate_headers(model, additional_headers, combined_pdf, header_footer_download_path, template_name = nil)
    # Get the headers
    headers = get_headers(model, template_name, additional_headers)
    Rails.logger.debug { "headers are #{headers.map(&:name)}" }
    return if headers.empty?

    headers.each do |header|
      process_header(header, combined_pdf, header_footer_download_path)
    end
  end

  def get_headers(model, template_name, additional_headers)
    headers = model.documents.where(name: ["Header", "Stamp Paper", "#{template_name} Header", "#{template_name} Stamp Paper"]).to_a
    headers += additional_headers if additional_headers.present?
    headers
  end

  def process_header(header, combined_pdf, header_footer_download_path)
    src_path = get_doc_pdf_path(header) # ok to reuse; name is just cosmetic
    header_footer_download_path << src_path
    Rails.logger.debug { "Adding header #{src_path}" }

    append_pdf(combined_pdf, src_path)
  rescue StandardError => e
    msg = "Error adding Header: #{header.name}: #{e.message}"
    Rails.logger.error { msg }
    raise msg
  end

  def generate_footers(model, additional_footers, combined_pdf, header_footer_download_path, template_name = nil)
    footers = get_footers(model, template_name, additional_footers)
    Rails.logger.debug { "footers are #{footers.map(&:name)}" }
    return if footers.empty?

    footers.each do |footer|
      process_footer(footer, combined_pdf, header_footer_download_path)
    end
  end

  def process_footer(footer, combined_pdf, header_footer_download_path)
    src_path = get_doc_pdf_path(footer)
    header_footer_download_path << src_path
    Rails.logger.debug { "Adding footer #{src_path}" }

    append_pdf(combined_pdf, src_path)
  rescue StandardError => e
    msg = "Error adding Footer: #{footer.name}: #{e.message}"
    Rails.logger.error { msg }
    raise msg
  end

  # --------------------------
  # UTILITIES
  # --------------------------

  def append_pdf(dest_doc, src_path)
    src = HexaPDF::Document.open(src_path)
    src.pages.each { |page| dest_doc.pages << dest_doc.import(page) }
  end

  # Converts images to PDFs
  def get_doc_pdf_path(document)
    file = document.file.download
    if IMAGE_EXTENSIONS.include?(File.extname(file.path).downcase)
      Libreconv.convert(file.path, "#{file.path}.pdf")
      "#{file.path}.pdf"
    else
      file.path
    end
  end

  def get_footers(model, template_name, additional_footers)
    footers = model.documents.where(name: ["Footer", "#{template_name} Footer", "#{template_name} Signature"]).to_a
    footers += additional_footers if additional_footers.present?
    footers
  end

  # --------------------------
  # NOTIFICATIONS / UPLOAD
  # --------------------------

  def send_notification(message, user_id, level = "success")
    UserAlert.new(user_id:, message:, level:).broadcast
  end

  def upload(doc_template, model, start_date = nil, end_date = nil, folder = nil, generated_document_name = nil, user_id: nil, file_extension: "pdf", as_of: nil)
    file_name = "#{generated_file_name(model)}.#{file_extension}"
    Rails.logger.debug { "Uploading generated file #{file_name} to #{model} " }

    # Clone some attributes of the template
    generated_document = Document.new(doc_template.attributes.slice("entity_id", "name", "orignal", "download", "printing", "user_id", "display_on_page", "force_esign_order"))

    generated_document.name = generated_document_name ||
                              if start_date && end_date
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
    generated_document.user_id = user_id if user_id.present?

    # Add the e-signatures and stamp papers if available
    generated_document.e_signatures = doc_template.e_signatures_for(model) || []
    errors = []
    generated_document.e_signatures.each do |esign|
      esign.document = generated_document
      esign.entity = model.entity
      errors << esign.errors.full_messages.join(", ") unless esign.valid?
    end
    # shows proper error messages
    raise errors.join(", ") if errors.any?

    generated_document.stamp_papers = doc_template.stamp_papers_for(model) || []
    generated_document.as_of = as_of

    generated_document.save!
  end
end
