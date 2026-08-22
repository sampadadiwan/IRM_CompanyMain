require "hexapdf"
require "open3"
require "json"
require "fileutils"

module DocumentGeneratorBase
  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif].freeze

  # The Document record created by the most recent #upload call, if any.
  # Portfolio report gen needs this to combine all portfolio reports into one
  attr_reader :generated_document

  def convert(template, context, file_name, to_pdf: true, template_name: nil)
    # Mail Merge
    file_path = File.expand_path("#{file_name}.docx")
    Rails.logger.debug { "#{self.class} Generating document at #{file_path}" }
    template.render_to_file(file_path, context)

    # Run DOCX post-processor atomically: take a backup so we can restore the original
    # if it fails mid-write, preventing a half-processed file from being used.
    #
    # DocxNumberingFixer deliberately NOT run here — it's for TemplateFixAgent's own
    # documented pattern (a hidden vanish-flagged counter-setter paragraph confusing
    # LibreOffice's list numbering) and must never run silently on every generated
    # document. Only the reported/fixed template should ever go through it.
    backup_path = "#{file_path}.bak"
    FileUtils.cp(file_path, backup_path)
    begin
      # Bake resolved style properties (fonts, sizes, indentation) directly into
      # paragraphs/runs so LibreOffice doesn't mis-read the style inheritance
      # chain and produce wrong fonts or indentation in the PDF.
      DocxFormattingPreserver.apply!(file_path)
    rescue StandardError => e
      Rails.logger.error { "[DocumentGeneratorBase] DOCX post-processing failed (#{e.class}): #{e.message}; restoring original" }
      FileUtils.mv(backup_path, file_path)
      raise
    ensure
      FileUtils.rm_f(backup_path) if File.exist?(backup_path)
    end

    if to_pdf
      # Convert to PDF with accessibility tags
      convert_to_accessible_pdf(file_name, template_name)
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

  def add_header_footers(model, spa_path, additional_headers = nil, additional_footers = nil, template_name = nil, file_name: nil)
    header_footer_download_path = []

    # Open the SPA PDF first to capture accessibility metadata
    spa_doc = HexaPDF::Document.open("#{spa_path}.pdf")

    # Create a new document and preserve accessibility metadata from SPA
    combined_pdf = HexaPDF::Document.new
    preserve_accessibility_metadata(combined_pdf, spa_doc)
    set_pdf_metadata(combined_pdf, model, template_name, file_name)

    generate_headers(model, additional_headers, combined_pdf, header_footer_download_path, template_name)

    # Combine the SPA PDF
    append_pdf(combined_pdf, "#{spa_path}.pdf")

    generate_footers(model, additional_footers, combined_pdf, header_footer_download_path, template_name)

    # Save final PDF
    # Write to a temp file first to avoid overwriting the source file (spa_path.pdf)
    # while it is still being read by HexaPDF (lazy loading).
    temp_output_path = "#{spa_path}_temp.pdf"
    begin
      combined_pdf.write(temp_output_path, optimize: true)
    rescue StandardError => e
      Rails.logger.warn("PDF validation error for #{spa_path}: #{e.message}")
      combined_pdf.write(temp_output_path, optimize: true, validate: false)
    end

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

  def preserve_accessibility_metadata(dest_doc, src_doc)
    # Copy language setting if present
    dest_doc.catalog[:Lang] = dest_doc.import(src_doc.catalog[:Lang]) if src_doc.catalog[:Lang]

    # Copy MarkInfo if present
    dest_doc.catalog[:MarkInfo] = dest_doc.import(src_doc.catalog[:MarkInfo]) if src_doc.catalog[:MarkInfo]

    # Copy StructTreeRoot if present (structure tree for tagged PDF)
    dest_doc.catalog[:StructTreeRoot] = dest_doc.import(src_doc.catalog[:StructTreeRoot]) if src_doc.catalog[:StructTreeRoot]

    # Copy ViewerPreferences if present (document display settings)
    dest_doc.catalog[:ViewerPreferences] = dest_doc.import(src_doc.catalog[:ViewerPreferences]) if src_doc.catalog[:ViewerPreferences]

    # Ensure language is set (required for PDF/UA)
    dest_doc.catalog[:Lang] = "en-US" unless dest_doc.catalog[:Lang]
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
  # PDF METADATA & SETTINGS
  # --------------------------

  def set_pdf_metadata(pdf_doc, model = nil, template_name = nil, file_name = nil)
    # Set document information dictionary with required metadata
    # Works for both model-aware (header/footer) and generic (standalone PDF) scenarios
    info = pdf_doc.trailer[:Info] || {}

    # Determine author
    author = if model
               model.entity&.to_s || model.to_s
             else
               "Caphive Document Generator"
             end

    # Title: Use template name or file_name or model identifier
    info[:Title] = if template_name.present?
                     template_name.to_s
                   elsif file_name.present?
                     File.basename(file_name, ".pdf")
                   elsif model
                     "Generated document for #{model}"
                   else
                     "Generated Document"
                   end

    info[:Author] = author

    # Subject: Include context if available (clean up empty template names)
    template_name_str = template_name.to_s.strip
    info[:Subject] = if template_name_str.present?
                       "Generated document: #{template_name_str}"
                     elsif model
                       "Generated document for #{model}"
                     else
                       "Generated document"
                     end

    # Keywords: For searchability
    keywords_parts = %w[Generated document]
    keywords_parts << template_name_str.downcase if template_name_str.present?
    keywords_parts << model.class.name.downcase if model
    info[:Keywords] = keywords_parts.join(", ")

    # Creator: Application that created the document
    info[:Creator] = "HexaPDF for #{author}"

    # Producer: PDF library being used
    info[:Producer] = "HexaPDF #{HexaPDF::VERSION}"

    # Creation and modification timestamps (convert to PDF date format)
    now = Time.current
    pdf_date = format_pdf_date(now)
    info[:CreationDate] = pdf_date
    info[:ModDate] = pdf_date

    pdf_doc.trailer[:Info] = info

    # Set viewer preferences for better accessibility
    pdf_doc.catalog[:ViewerPreferences] ||= {}
    pdf_doc.catalog[:ViewerPreferences][:DisplayDocTitle] = true

    # Add XMP metadata stream (required for PDF/UA-1)
    add_xmp_metadata(pdf_doc, info[:Title].to_s, author, info[:Subject].to_s)
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
    model.reload # Reload to get latest lock_version (destroying docs above touches the owner, incrementing lock_version)
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
    @generated_document = generated_document
  end

  def convert_to_accessible_pdf(file_name, template_name = nil)
    docx_path = "#{file_name}.docx"
    pdf_dir   = File.dirname(File.expand_path(docx_path))
    pdf_path  = "#{file_name}.pdf"

    pdf_options = {
      "UseTaggedPDF" => {
        "type" => "boolean",
        "value" => "true"
      },
      "PDFUACompliance" => {
        "type" => "boolean",
        "value" => "true"
      },
      "ExportBookmarks" => {
        "type" => "boolean",
        "value" => "true"
      },
      "UseLosslessCompression" => {
        "type" => "boolean",
        "value" => "true"
      },
      "SignPDF" => {
        "type" => "boolean",
        "value" => "false"
      }
    }

    filter = "pdf:writer_pdf_Export:#{JSON.generate(pdf_options)}"

    cmd = [
      "soffice",
      "--headless",
      "--convert-to", filter,
      "--outdir", pdf_dir,
      docx_path
    ]

    stdout, stderr, status = Open3.capture3(*cmd)

    raise "LibreOffice PDF conversion failed\nSTDOUT: #{stdout}\nSTDERR: #{stderr}" unless status.success?

    # Post-process the generated PDF to add required metadata
    pdf = HexaPDF::Document.open(pdf_path)

    # Ensure language is set (required for PDF/UA)
    pdf.catalog[:Lang] ||= "en-US"

    # Ensure MarkInfo is set (indicates tagged PDF)
    pdf.catalog[:MarkInfo] ||= { Marked: true }

    # Use set_pdf_metadata for consistent metadata across all PDFs
    set_pdf_metadata(pdf, nil, template_name, file_name)

    # Write to a temp file first to avoid overwriting the source file (pdf_path)
    # while it is still being read by HexaPDF (lazy loading).
    temp_output_path = "#{pdf_path}.tmp"
    begin
      pdf.write(temp_output_path, optimize: true)
    rescue StandardError => e
      Rails.logger.warn("PDF validation error for #{pdf_path}: #{e.message}")
      pdf.write(temp_output_path, optimize: true, validate: false)
    end
    FileUtils.mv(temp_output_path, pdf_path)
  end

  # --------------------------
  # HELPER METHODS
  # --------------------------

  def format_pdf_date(time_obj)
    # PDF date format: D:YYYYMMDDHHmmSSOHH'mm'
    # Example: D:20260525121630+05'30'
    # %z produces +0530, but we need +05'30' with apostrophes
    base = time_obj.strftime("D:%Y%m%d%H%M%S")
    tz_offset = time_obj.strftime("%z")

    # Convert +0530 to +05'30'
    tz_formatted = if tz_offset.match?(/^[+-]\d{4}$/)
                     "#{tz_offset[0..2]}'#{tz_offset[3..]}'"
                   else
                     "+00'00'"
                   end

    "#{base}#{tz_formatted}"
  end

  def add_xmp_metadata(pdf_doc, title, author, subject)
    # Create XMP metadata stream (required for PDF/UA-1)
    # XMP is an XML-based metadata format embedded in PDFs
    now = Time.current.iso8601

    xmp_content = <<~XMP
      <?xml version="1.0" encoding="UTF-8"?>
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
               xmlns:dc="http://purl.org/dc/elements/1.1/"
               xmlns:xmp="http://ns.adobe.com/xap/1.0/"
               xmlns:pdf="http://ns.adobe.com/pdf/1.3/"
               xmlns:pdfuaid="http://www.aiim.org/pdfua/ns/id/">
        <rdf:Description rdf:about=""
                         xmp:CreatorTool="HexaPDF"
                         pdf:Producer="HexaPDF #{HexaPDF::VERSION}"
                         pdfuaid:part="1"
                         pdfuaid:conformance="a">
          <dc:title>
            <rdf:Alt>
              <rdf:li xml:lang="x-default">#{escape_xml(title)}</rdf:li>
            </rdf:Alt>
          </dc:title>
          <dc:creator>
            <rdf:Seq>
              <rdf:li>#{escape_xml(author)}</rdf:li>
            </rdf:Seq>
          </dc:creator>
          <dc:subject>
            <rdf:Seq>
              <rdf:li>#{escape_xml(subject)}</rdf:li>
            </rdf:Seq>
          </dc:subject>
          <dc:date>
            <rdf:Seq>
              <rdf:li>#{now}</rdf:li>
            </rdf:Seq>
          </dc:date>
        </rdf:Description>
      </rdf:RDF>
    XMP

    # Create metadata stream object using HexaPDF's proper API
    # Stream dictionary defines the stream's properties, stream: parameter contains the actual content
    metadata_dict = {
      Type: :Metadata,
      Subtype: :XML,
      Length: xmp_content.bytesize
    }

    metadata_stream = pdf_doc.add(metadata_dict, stream: xmp_content)

    # Attach to catalog
    pdf_doc.catalog[:Metadata] = metadata_stream
  end

  def escape_xml(text)
    # Escape XML special characters
    text.to_s
        .gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
        .gsub('"', "&quot;")
        .gsub("'", "&apos;")
  end

  # Extract mail merge fields from a Word template
  # @param template_path [String] Path to the .docx file
  # @param filter_pattern [String, Regexp, Array, nil] Optional regex, string, or array of patterns to filter field names
  # @return [Array<String>] List of mail merge field names
  def extract_merge_fields(template_path, filter_pattern = nil)
    require "zip"
    require "nokogiri"

    merge_fields = []

    begin
      Zip::File.open(template_path) do |zip|
        # Read document.xml from the .docx (which is a ZIP archive)
        if zip.find_entry("word/document.xml")
          doc_xml = zip.read("word/document.xml")
          doc = Nokogiri::XML(doc_xml)

          # Word uses namespaces; define the namespace properly
          ns = { "w" => "http://schemas.openxmlformats.org/wordprocessingml/2006/main" }

          # Find all instrText elements (Field Instructions in Word)
          # They contain text like: MERGEFIELD field_name \* MERGEFORMAT
          doc.xpath("//w:instrText", ns).each do |instr_node|
            instr_text = instr_node.text.to_s.strip

            # Check if this is a MERGEFIELD instruction
            next unless instr_text.include?("MERGEFIELD")

            # Extract the field name (between MERGEFIELD and the next space or backslash)
            match = instr_text.match(/MERGEFIELD\s+([^\s\\]+)/i)
            field_name = match[1] if match

            next unless field_name

            merge_fields << field_name if matches_filter_pattern?(field_name, filter_pattern)
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error { "Error extracting merge fields from #{template_path}: #{e.message}" }
      return []
    end

    merge_fields.map do |field|
      field.to_s.strip.split(":").first
    end.uniq
  end

  private

  def matches_filter_pattern?(field_name, filter_pattern)
    return true if filter_pattern.nil?

    patterns = filter_pattern.is_a?(Array) ? filter_pattern : [filter_pattern]

    patterns.any? do |pattern|
      case pattern
      when Regexp
        field_name.match?(pattern)
      when String
        field_name.include?(pattern)
      else
        false
      end
    end
  end

  # Check if template has any merge fields containing a specific pattern
  # @param template_path [String] Path to the .docx file
  # @param pattern [String] Pattern to search for (e.g., 'aes_')
  # @return [Boolean] True if template contains matching fields
  def template_has_merge_field_pattern?(template_path, pattern)
    fields = extract_merge_fields(template_path, pattern)
    fields.any?
  end

  # Get all merge fields containing a specific pattern
  # @param template_path [String] Path to the .docx file
  # @param pattern [String] Pattern to search for (e.g., 'aes_')
  # @return [Array<String>] List of matching field names
  def merge_fields_with_pattern(template_path, pattern)
    extract_merge_fields(template_path, pattern)
  end
end
