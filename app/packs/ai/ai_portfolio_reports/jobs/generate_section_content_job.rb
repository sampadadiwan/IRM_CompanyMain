# rubocop:disable Metrics/ClassLength
# Background job to generate AI report section content from documents.
class GenerateSectionContentJob < ApplicationJob
  queue_as :default

  DOCUMENT_FOLDER_PATH = "/tmp/test_documents".freeze

  # Generate content for each report section.
  #
  # @param report_id [Integer] report ID
  # @return [void]
  def perform(report_id)
    report = AiPortfolioReport.find(report_id)

    Rails.logger.info "=== Starting generation for report #{report_id} ==="

    # Downloaded documents to local folder
    download_folder_documents(report.folder)

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

        next if section.section_type == "Custom Charts"

        # SPECIAL HANDLING: Investment Fit section
        if section.section_type == "Investment Fit Evaluation"
          generate_investment_fit_section(report, section, cached_documents_context)
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

  # Download folder documents to local disk for processing.
  #
  # @param folder [Folder, nil] document folder
  # @return [void]
  def download_folder_documents(folder)
    return if folder.nil?

    FileUtils.rm_rf(DOCUMENT_FOLDER_PATH)
    FileUtils.mkdir_p(DOCUMENT_FOLDER_PATH)

    return if folder.nil?

    Rails.logger.info "[GenerateSectionContentJob] Downloading documents for folder ID: #{folder.name}"

    supported_extensions = %w[.pdf .txt .md .docx .xlsx .xls .pptx .ppt .csv]

    folder.documents.each do |doc|
      next if doc.file.blank?

      begin
        # filename = doc.file.original_filename
        filename = File.basename(doc.file.original_filename).gsub(/[^0-9A-Za-z.\-_]/, '_')

        extension = File.extname(filename).downcase
        next unless supported_extensions.include?(extension)

        file_path = File.join(DOCUMENT_FOLDER_PATH, filename)

        doc.file.open do |io|
          File.binwrite(file_path, io.read)
        end

        Rails.logger.info "[GenerateSectionContentJob] Downloaded: #{filename}"
      rescue StandardError => e
        Rails.logger.error "[GenerateSectionContentJob] Failed to download #{doc.name}: #{e.message}"
      end
    end
  end

  # Auto-generate charts for a section if chartable data exists.
  #
  # @param report [AiPortfolioReport] report context
  # @param section [AiReportSection] section to update
  # @return [void]
  def generate_section_charts_if_data_exists(report, section)
    Rails.logger.info "  → Checking for chartable data: #{section.section_type}"

    generator = ChartSectionGenerator.new(report: report, section: section, cached_document_paths: @document_paths)

    # Get data preview to check if chartable data exists
    document_paths = generator.find_csv_documents
    data_preview = generator.extract_data_preview(document_paths)

    return if data_preview.blank?

    # Ask LLM if chartable data exists for this section type
    chart_prompts = check_and_generate_chart_prompts(section.section_type, data_preview)

    if chart_prompts.present?
      Rails.logger.info "  → Generating #{chart_prompts.count} charts for #{section.section_type}"
      charts_html = generator.generate_charts_html(chart_prompts: chart_prompts)

      # Append charts to existing content
      updated_content = section.content_html.to_s + charts_html
      section.update(content_html: updated_content)

      Rails.logger.info "  ✓ Added #{section.agent_chart_ids.count} charts to #{section.section_type}"
    else
      Rails.logger.info "  → No chartable data found for #{section.section_type}"
    end
  rescue StandardError => e
    Rails.logger.error "  ✗ Chart generation failed for #{section.section_type}: #{e.message}"
  end

  # Check if document data has chartable information for this section.
  #
  # @param section_type [String] section type name
  # @param data_preview [String] document data preview
  # @return [Array<String>] chart prompts
  def check_and_generate_chart_prompts(section_type, data_preview)
    chat = RubyLLM.chat(model: ENV.fetch("DEFAULT_MODEL", nil))

    prompt = <<~PROMPT
      Analyze the following document data and determine if there is numerical/chartable data relevant to a "#{section_type}" section.

      DATA:
      #{data_preview[0..4000]}

      TASK:
      - If chartable data exists (numbers, percentages, trends, comparisons), return 1-2 chart prompts as a JSON array
      - If NO chartable data exists, return an empty array: []
      - Be strict: only suggest charts if clear numerical data is present
      - Do not invent or assume data that isn't there

      Examples of valid chart prompts:
      - "Revenue growth over 2022-2024 as a line chart"
      - "Market share breakdown as a pie chart"
      - "Funding rounds comparison as a bar chart"

      Return ONLY a JSON array, nothing else.
    PROMPT

    response = chat.ask(prompt)
    result = response.content.strip.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")

    prompts = JSON.parse(result)
    prompts.is_a?(Array) ? prompts : []
  rescue StandardError => e
    Rails.logger.error "Error checking for chartable data: #{e.message}"
    []
  end

  # Load documents once and return the formatted context string.
  #
  # @param folder_path [String] folder path
  # @return [String] formatted document context
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

  # Extract text from file based on extension.
  #
  # @param file_path [String] file path
  # @param extension [String] file extension
  # @return [String] extracted text
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

  # Extract text from a PDF file.
  #
  # @param file_path [String] PDF path
  # @return [String] extracted text
  def extract_pdf_text(file_path)
    require 'pdf-reader'
    reader = PDF::Reader.new(file_path)
    reader.pages.first(100).map(&:text).join("\n\n")
  rescue StandardError => e
    "Error extracting PDF: #{e.message}"
  end

  # Extract text from an Excel file.
  #
  # @param file_path [String] Excel path
  # @return [String] extracted text
  def extract_excel_text(file_path)
    require 'roo'
    spreadsheet = Roo::Spreadsheet.open(file_path)
    text_parts = []

    spreadsheet.sheets.first(5).each do |sheet_name|
      sheet = spreadsheet.sheet(sheet_name)
      text_parts << "=== Sheet: #{sheet_name} ==="

      rows = []
      sheet.each_row_streaming(pad_cells: true, max_rows: 100) do |row|
        row_values = row.map { |cell| cell&.value.to_s.strip }.compact_blank
        rows << row_values.join(" | ") if row_values.any?
      end

      text_parts << rows.join("\n")
    end

    text_parts.join("\n\n")
  rescue StandardError => e
    "Error extracting Excel: #{e.message}"
  end

  # Extract text from a PowerPoint file.
  #
  # @param file_path [String] PowerPoint path
  # @return [String] extracted text
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

        texts = doc.xpath('//t').map(&:text).compact_blank
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

  # Extract chart data from a document snippet.
  #
  # @param chart_doc [String] document snippet
  # @return [String] extracted chart data
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

  # Format documents for LLM consumption.
  #
  # @param documents [Array<Hash>] document entries
  # @return [String] formatted context
  def format_documents_for_llm(documents)
    return "No documents available." if documents.empty?

    formatted = documents.map do |doc|
      "=== Document: #{doc[:name]} ===\n#{doc[:content]}\n"
    end

    formatted.join("\n---\n\n")
  end

  # Generate charts using Rails ChartSectionGenerator
  # Generate charts for a section.
  #
  # @param report [AiPortfolioReport] report context
  # @param section [AiReportSection] section to update
  # @return [void]
  def generate_charts_section(report, section)
    Rails.logger.info "  → Using Rails ChartSectionGenerator"

    # generator = ChartSectionGenerator.new(report: report, section: section)
    generator = ChartSectionGenerator.new(report: report, section: section, cached_document_paths: @document_paths)

    html = generator.generate_charts_html

    section.update(content_html: html)

    Rails.logger.info "  ✓ Generated #{section.agent_chart_ids.count} charts"
  end

  # Save extracted text to disk for inspection.
  #
  # @param text [String] extracted text
  # @param report_id [Integer] report ID
  # @return [void]
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
  # Generate text for a section using cached documents.
  #
  # @param report [AiPortfolioReport] report context
  # @param section [AiReportSection] section to update
  # @param cached_documents_context [String] cached document context
  # @return [void]
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

      # Auto-generate charts for eligible sections if document data supports it
      generate_section_charts_if_data_exists(report, section) if AiPortfolioReport::CHART_ELIGIBLE_SECTIONS.include?(section.section_type)

    else
      error_msg = result['error'] || result[:error] || result.inspect
      Rails.logger.error "  ✗ Failed #{section.section_type}: #{error_msg}"
      Rails.logger.error "Result keys: #{result.keys.inspect}"
    end
  end

  # Collect document paths from the local folder.
  #
  # @param folder_path [String] folder path
  # @return [Array<String>] document paths
  def collect_document_paths(folder_path)
    return [] unless folder_path.present? && Dir.exist?(folder_path)

    supported_extensions = %w[.pdf .txt .md .docx .xlsx .xls .pptx .ppt .csv]
    Dir.glob(File.join(folder_path, "*")).select do |file_path|
      File.file?(file_path) && supported_extensions.include?(File.extname(file_path).downcase)
    end
  end

  def generate_investment_fit_section(report, section, cached_documents_context)
    template = report.investment_criteria_template

    # If no template selected, mark section as skipped
    if template.nil?
      section.update(
        content_html: investment_fit_not_configured_html,
        status: 'skipped'
      )
      Rails.logger.info "  → Investment Fit skipped (no template)"
      return
    end

    Rails.logger.info "  → Generating Investment Fit with template: #{template.name}"

    # Use InvestmentFitSectionGenerator (new service)
    generator = InvestmentFitSectionGenerator.new(
      report: report,
      section: section,
      template: template,
      pitch_deck_content: cached_documents_context
    )

    html_content = generator.generate
    section.update(content_html: html_content)

    # Increment template usage
    template.update!(usage_count: template.usage_count + 1)

    Rails.logger.info "  ✓ Generated Investment Fit section"
  end

  def investment_fit_not_configured_html
    <<~HTML
      <div class="investment-fit-not-configured" style="padding: 2rem; background: #f8f9fa; border-radius: 8px; text-align: center;">
        <h3 style="color: #6b7280;">Investment Fit Evaluation Not Configured</h3>
        <p style="color: #9ca3af;">
          No investment criteria template was selected for this report.
          To generate an Investment Fit evaluation, edit the report and select a template.
        </p>
      </div>
    HTML
  end
end
# rubocop:enable Metrics/ClassLength
