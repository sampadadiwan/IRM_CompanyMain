class GenerateSectionContentJob < ApplicationJob
  queue_as :default

  DOCUMENT_FOLDER_PATH = "/tmp/test_documents"

  def perform(report_id)
    report = AiPortfolioReport.find(report_id)

    Rails.logger.info "=== Starting generation for report #{report_id} ==="

    @document_paths = collect_document_paths(DOCUMENT_FOLDER_PATH)
    # OPTIMIZATION: Load documents ONCE at the start, cache for all sections
    cached_documents_context = load_documents_once(DOCUMENT_FOLDER_PATH)

    Rails.logger.info "=== Documents loaded once: #{cached_documents_context.length} chars ==="

    # DEBUG: Save extracted text to file for inspection
    save_extracted_text_for_inspection(cached_documents_context, report_id)

    report.ai_report_sections.each do |section|
      # Skip if already has content
      next if section.content_html.present?

      begin
        Rails.logger.info "Generating: #{section.section_type}"

<<<<<<< HEAD
        # next unless section.section_type == "Custom Charts"
=======
        # next unless section.section_type == "Company Overview"
>>>>>>> main

        # next unless ["Company Overview", "Key Products & Services"].include?(section.section_type) # Skip this section as per requirements

        # SPECIAL HANDLING: Custom Charts section uses Rails service
        if section.section_type == "Custom Charts"
          generate_charts_section(report, section)
          next
        else
          # All other sections use PortfolioReportAgent with cached documents
          generate_text_section(report, section, cached_documents_context)
        end
      rescue StandardError => e
        Rails.logger.error "Error: #{section.section_type}: #{e.message}"
      end

      sleep(2) # Rate limiting
    end

    Rails.logger.info "=== Completed generation for report #{report_id} ==="
  end

  private

  # Load documents ONCE and return the formatted context string
  def load_documents_once(folder_path)
    return "" unless folder_path.present? && Dir.exist?(folder_path)

    Rails.logger.info "[GenerateSectionContentJob] Loading documents from: #{folder_path}"

    documents = []
    supported_extensions = %w[.pdf .txt .md .docx .xlsx .xls .pptx .ppt]

    Dir.glob(File.join(folder_path, "*")).each do |file_path|
      next unless File.file?(file_path)

      extension = File.extname(file_path).downcase
      next unless supported_extensions.include?(extension)

      begin
        Rails.logger.info "[GenerateSectionContentJob] Extracting: #{File.basename(file_path)}"
        text = extract_text_from_file(file_path, extension)

        documents << {
          name: File.basename(file_path),
          content: text[0..5000]
        }

        break if documents.count >= 10
      rescue StandardError => e
        Rails.logger.warn "[GenerateSectionContentJob] Could not extract: #{file_path} - #{e.message}"
      end
    end

    format_documents_for_llm(documents)
  end

  # Extract text from file based on extension
  def extract_text_from_file(file_path, extension)
    case extension
    when '.txt', '.md'
      File.read(file_path, encoding: 'UTF-8')
    when '.pdf'
      extract_pdf_text(file_path)
    when '.xlsx', '.xls'
      extract_excel_text(file_path)
    when '.pptx', '.ppt'
      extract_pptx_text(file_path)
    else
      "Cannot extract text from #{extension} files"
    end
  end

  def extract_pdf_text(file_path)
    require 'pdf-reader'
    reader = PDF::Reader.new(file_path)
    reader.pages.first(100).map(&:text).join("\n\n")
  rescue StandardError => e
    "Error extracting PDF: #{e.message}"
  end

  def extract_excel_text(file_path)
    require 'roo'
    spreadsheet = Roo::Spreadsheet.open(file_path)
    text_parts = []

    spreadsheet.sheets.first(5).each do |sheet_name|
      sheet = spreadsheet.sheet(sheet_name)
      text_parts << "=== Sheet: #{sheet_name} ==="

      rows = []
      sheet.each_row_streaming(pad_cells: true, max_rows: 100) do |row|
        row_values = row.map { |cell| cell&.value.to_s.strip }.reject(&:blank?)
        rows << row_values.join(" | ") if row_values.any?
      end

      text_parts << rows.join("\n")
    end

    text_parts.join("\n\n")
  rescue StandardError => e
    "Error extracting Excel: #{e.message}"
  end

  def extract_pptx_text(file_path)
    require 'zip'
    require 'nokogiri'

    text_parts = []
    slide_number = 0

    Zip::File.open(file_path) do |zip_file|
      # Extract slide text
      slide_entries = zip_file.glob('ppt/slides/slide*.xml').sort_by do |entry|
        entry.name.match(/slide(\d+)\.xml/)[1].to_i
      end

      slide_entries.first(30).each do |entry|
        slide_number += 1
        content = entry.get_input_stream.read
        doc = Nokogiri::XML(content)
        doc.remove_namespaces!

        texts = doc.xpath('//t').map(&:text).reject(&:blank?)
        if texts.any?
          text_parts << "=== Slide #{slide_number} ==="
          text_parts << texts.join("\n")
        end
      end

      # Extract chart data
      chart_entries = zip_file.glob('ppt/charts/chart*.xml')
      chart_entries.first(10).each_with_index do |entry, idx|
        chart_content = entry.get_input_stream.read
        chart_doc = Nokogiri::XML(chart_content)
        chart_doc.remove_namespaces!

        chart_data = extract_chart_data(chart_doc)
        if chart_data.present?
          text_parts << "=== Chart #{idx + 1} Data ==="
          text_parts << chart_data
        end
      end
    end

    text_parts.join("\n\n").presence || "No text content found in PowerPoint"
  rescue StandardError => e
    "Error extracting PPTX: #{e.message}"
  end

  def extract_chart_data(chart_doc)
    data_parts = []

    title = chart_doc.xpath('//title//t').map(&:text).join(' ')
    data_parts << "Title: #{title}" if title.present?

    chart_doc.xpath('//ser').each do |series|
      series_name = series.xpath('.//tx//v | .//tx//t').first&.text
      data_parts << "Series: #{series_name}" if series_name.present?

      categories = series.xpath('.//cat//v | .//cat//t').map(&:text)
      values = series.xpath('.//val//v').map(&:text)

      if categories.any? && values.any?
        categories.zip(values).each do |cat, val|
          data_parts << "  #{cat}: #{val}" if cat.present? || val.present?
        end
      elsif values.any?
        data_parts << "  Values: #{values.first(10).join(', ')}"
      end
    end

    data_parts.join("\n")
  end

  def format_documents_for_llm(documents)
    return "No documents available." if documents.empty?

    formatted = documents.map do |doc|
      "=== Document: #{doc[:name]} ===\n#{doc[:content]}\n"
    end

    formatted.join("\n---\n\n")
  end

  # Generate charts using Rails ChartSectionGenerator
  def generate_charts_section(report, section)
    Rails.logger.info "  → Using Rails ChartSectionGenerator"

    # generator = ChartSectionGenerator.new(report: report, section: section)
    generator = ChartSectionGenerator.new(report: report, section: section, cached_document_paths: @document_paths)

    html = generator.generate_charts_html

    section.update(content_html: html)

    Rails.logger.info "  ✓ Generated #{section.agent_chart_ids.count} charts"
  end

  def save_extracted_text_for_inspection(text, report_id)
    file_path = "/tmp/generated_txt.txt"

    # Ensure text is string
    sanitized_text = text.to_s

    # Write to file
    File.open(file_path, "w") do |f|
      f.puts "=== Extracted Text for Report ID: #{report_id} ==="
      f.puts sanitized_text
    end

    Rails.logger.info "[DEBUG] Extracted text saved to #{file_path}"
  rescue StandardError => e
    Rails.logger.error "[ERROR] Failed to save extracted text: #{e.message}"
  end

  # Generate text using PortfolioReportAgent with cached documents
  def generate_text_section(report, section, cached_documents_context)
    Rails.logger.info "  → Using PortfolioReportAgent (with cached documents)"

    # Find or create PortfolioReportAgent
    agent = SupportAgent.find_or_create_by!(
      agent_type: 'PortfolioReportAgent',
      entity_id: report.analyst.entity_id
    ) do |a|
      a.name = 'Portfolio Report Generator'
      a.enabled = true
    end

    # Call PortfolioReportAgent with pre-loaded documents context
    result = PortfolioReportAgent.call(
      support_agent_id: agent.id,
      target: section,
      action: 'generate',
      cached_documents_context: cached_documents_context, # Pass cached context
      web_search_enabled: false
    )

    if result.success?
      Rails.logger.info "  ✓ Generated #{section.section_type}"
    else
      error_msg = result['error'] || result[:error] || result.inspect
      Rails.logger.error "  ✗ Failed #{section.section_type}: #{error_msg}"
      Rails.logger.error "Result keys: #{result.keys.inspect}"
    end
  end

  def collect_document_paths(folder_path)
    return [] unless folder_path.present? && Dir.exist?(folder_path)

    supported_extensions = %w[.pdf .txt .md .docx .xlsx .xls .pptx .ppt .csv]
    Dir.glob(File.join(folder_path, "*")).select do |file_path|
      File.file?(file_path) && supported_extensions.include?(File.extname(file_path).downcase)
    end
  end
end
