# app/packs/ai/ai_portfolio_reports/services/chart_section_generator.rb
# rubocop:disable Metrics/ClassLength
class ChartSectionGenerator
  def initialize(report:, section:, cached_document_paths: nil)
    @report = report
    @section = section
    @portfolio_company = report.portfolio_company
    @entity = @portfolio_company.entity
    @cached_document_paths = cached_document_paths
    @cached_data_preview = @section.metadata&.dig('cached_data_preview')
    @converted_files_cache = {} # Cache converted temp files
    @temp_files_to_keep = [] # Keep Tempfile objects alive
  end

  # Main method: Generate charts and return HTML
  def generate_charts_html(chart_prompts: nil)
    # Clear any existing charts
    @section.agent_chart_ids = []

    # Find relevant documents
    document_paths = @cached_document_paths || find_csv_documents

    Rails.logger.info "=== Chart Generation Started ==="
    Rails.logger.info "Company: #{@portfolio_company.name}"
    Rails.logger.info "Documents found: #{document_paths.count}"

    # Extract data preview for LLM to analyze
    # data_preview = extract_data_preview(document_paths)

    data_preview = @cached_data_preview || extract_data_preview(document_paths)
    # Save to metadata for future use (refinements)
    @section.update(metadata: (@section.metadata || {}).merge('cached_data_preview' => data_preview)) unless @cached_data_preview
    @cached_data_preview = data_preview

    Rails.logger.info "Data preview length: #{data_preview.length} chars"

    # Generate chart prompts dynamically based on actual data (or use provided prompts)
    prompts = chart_prompts || generate_chart_prompts_from_data(data_preview)
    Rails.logger.info "Generated #{prompts.count} chart prompts: #{prompts.inspect}"

    # Generate each chart
    charts_html = ""
    prompts.each_with_index do |prompt, index|
      chart = create_chart(prompt, document_paths, index + 1)
      @section.add_chart(chart)
      charts_html += chart_to_html(chart)
    rescue StandardError => e
      Rails.logger.error "Failed to generate chart #{index + 1}: #{e.message}"
      charts_html += error_chart_html(prompt, e.message)
    end

    # Save the section
    @section.save

    Rails.logger.info "Generated #{@section.agent_chart_ids.count} charts"

    charts_html
  end

  # Add chart from user prompt
  def add_chart_from_prompt(user_prompt:)
    document_paths = @cached_document_paths || find_csv_documents

    Rails.logger.info "=== Adding Chart from Prompt ==="
    Rails.logger.info "User prompt: #{user_prompt}"
    Rails.logger.info "Documents found: #{document_paths.count}"

    existing_charts = @section.agent_charts.count
    chart_number = existing_charts + 1

    begin
      chart = create_chart(user_prompt, document_paths, chart_number)
      @section.add_chart(chart)

      Rails.logger.info "Added chart: #{chart.title}"

      chart_to_html(chart)
    rescue StandardError => e
      Rails.logger.error "Failed to add chart: #{e.message}"
      error_chart_html(user_prompt, e.message)
    end
  end

  private

  # Create a single chart using AgentChart + ChartAgentService
  def create_chart(prompt, document_paths, chart_number)
    # Normalize prompt if it's a Hash (from Gemini response)
    prompt = prompt.is_a?(Hash) ? (prompt['prompt'] || prompt[:prompt] || prompt.to_s) : prompt.to_s

    chart = AgentChart.create!(
      entity_id: @entity.id,
      title: "Chart #{chart_number}: #{extract_title(prompt)}",
      prompt: prompt,
      status: 'draft',
      owner: @report
    )

    # Convert all documents to CSV format for the chart service
    # temp_files = [] # Keep Tempfile objects alive
    # Use cached converted files if available, otherwise convert once
    temp_csv_paths = get_or_create_converted_files(document_paths)

    Rails.logger.info "[ChartSectionGenerator] using #{temp_csv_paths.count}"

    # document_paths.each do |original_path|
    #   extension = File.extname(original_path).downcase

    #   case extension
    #   when '.xlsx', '.xls'
    #     # Convert Excel to CSV
    #     csv_path = convert_excel_to_csv(original_path)
    #     temp_csv_paths << csv_path if csv_path
    #   when '.pptx', '.ppt'
    #     # Extract chart data from PPTX and convert to CSV
    #     csv_path = convert_pptx_to_csv(original_path)
    #     temp_csv_paths << csv_path if csv_path
    #   when '.csv'
    #     # Already CSV, just copy
    #     temp_file = Tempfile.new(['chart_data', '.csv'])
    #     FileUtils.cp(original_path, temp_file.path)
    #     temp_files << temp_file
    #     temp_csv_paths << temp_file.path
    #   when '.pdf'
    #     # Extract text from PDF
    #     temp_file, text_path = convert_pdf_to_text(original_path)
    #     if temp_file
    #       temp_files << temp_file
    #       temp_csv_paths << text_path
    #     end
    #   when '.docx', '.doc'
    #     # Extract text from DOCX
    #     temp_file, text_path = convert_docx_to_text(original_path)
    #     if temp_file
    #       temp_files << temp_file
    #       temp_csv_paths << text_path
    #     end
    #   else
    #     # Skip unsupported files
    #     Rails.logger.warn "[ChartSectionGenerator] Skipping unsupported file: #{File.basename(original_path)}"
    #   end
    # end

    Rails.logger.info "[ChartSectionGenerator] Converted #{temp_csv_paths.count} files to CSV for chart generation"

    # Generate the chart spec using existing ChartAgentService
    # chart.generate_spec!(csv_paths: temp_csv_paths)
    #
    ## Generate the chart spec using PortfolioChartAgentService (separate from Caphive's ChartAgentService)
    spec_hash = PortfolioChartAgentService.new(json_data: nil, csv_paths: temp_csv_paths, skip_cleanup: true).generate_chart!(prompt: prompt)
    chart.update!(spec: spec_hash, status: "ready")

    chart
  end

  def get_or_create_converted_files(document_paths)
    return @converted_files_cache[:paths] if @converted_files_cache[:paths].present?

    Rails.logger.info "[ChartSectionGenerator] Converting documents once (will be cached for all charts)"

    temp_csv_paths = []

    document_paths.each do |original_path|
      extension = File.extname(original_path).downcase

      case extension
      when '.xlsx', '.xls'
        csv_path = convert_excel_to_csv(original_path)
        temp_csv_paths << csv_path if csv_path
      when '.pptx', '.ppt'
        csv_path = convert_pptx_to_csv(original_path)
        temp_csv_paths << csv_path if csv_path
      when '.csv'
        temp_file = Tempfile.new(['chart_data', '.csv'])
        FileUtils.cp(original_path, temp_file.path)
        @temp_files_to_keep << temp_file
        temp_csv_paths << temp_file.path
      when '.pdf'
        temp_file, text_path = convert_pdf_to_text(original_path)
        if temp_file
          @temp_files_to_keep << temp_file
          temp_csv_paths << text_path
        end
      when '.docx', '.doc'
        temp_file, text_path = convert_docx_to_text(original_path)
        if temp_file
          @temp_files_to_keep << temp_file
          temp_csv_paths << text_path
        end
      else
        Rails.logger.warn "[ChartSectionGenerator] Skipping unsupported file: #{File.basename(original_path)}"
      end
    end

    @converted_files_cache[:paths] = temp_csv_paths
    temp_csv_paths
  end

  # Convert Excel file to CSV
  def convert_excel_to_csv(excel_path)
    require 'roo'
    require 'csv'

    Rails.logger.info "[ChartSectionGenerator] Converting Excel to CSV: #{File.basename(excel_path)}"

    spreadsheet = Roo::Spreadsheet.open(excel_path)
    temp_file = Tempfile.new(['excel_data', '.csv'])

    CSV.open(temp_file.path, 'wb') do |csv|
      # Use first sheet
      sheet = spreadsheet.sheet(spreadsheet.sheets.first)

      sheet.each_row_streaming(pad_cells: true, max_rows: 200) do |row|
        csv << row.map { |cell| cell&.value }
      end
    end

    Rails.logger.info "[ChartSectionGenerator] Excel converted to CSV: #{temp_file.path}"
    temp_file.path
  rescue StandardError => e
    Rails.logger.error "[ChartSectionGenerator] Error converting Excel: #{e.message}"
    nil
  end

  # Extract chart data from PPTX and convert to CSV
  def convert_pptx_to_csv(pptx_path)
    require 'zip'
    require 'nokogiri'
    require 'csv'

    Rails.logger.info "[ChartSectionGenerator] Extracting chart data from PPTX: #{File.basename(pptx_path)}"

    all_chart_data = []

    Zip::File.open(pptx_path) do |zip_file|
      chart_entries = zip_file.glob('ppt/charts/chart*.xml')

      chart_entries.each do |entry|
        chart_content = entry.get_input_stream.read
        chart_doc = Nokogiri::XML(chart_content)
        chart_doc.remove_namespaces!

        # Extract series data
        chart_doc.xpath('//ser').each do |series|
          series_name = series.xpath('.//tx//v | .//tx//t').first&.text || 'Series'
          categories = series.xpath('.//cat//v | .//cat//t').map(&:text)
          values = series.xpath('.//val//v').map(&:text)

          next unless categories.any? && values.any?

          categories.zip(values).each do |cat, val|
            all_chart_data << { category: cat, series: series_name, value: val }
          end
        end
      end
    end

    return nil if all_chart_data.empty?

    # Write to CSV
    temp_file = Tempfile.new(['pptx_chart_data', '.csv'])

    CSV.open(temp_file.path, 'wb') do |csv|
      csv << %w[Category Series Value]
      all_chart_data.each do |row|
        csv << [row[:category], row[:series], row[:value]]
      end
    end

    Rails.logger.info "[ChartSectionGenerator] PPTX chart data converted to CSV: #{temp_file.path} (#{all_chart_data.count} rows)"
    temp_file.path
  rescue StandardError => e
    Rails.logger.error "[ChartSectionGenerator] Error converting PPTX: #{e.message}"
    nil
  end

  # Convert PDF to text file
  def convert_pdf_to_text(pdf_path)
    require 'pdf-reader'

    Rails.logger.info "[ChartSectionGenerator] Extracting text from PDF: #{File.basename(pdf_path)}"

    reader = PDF::Reader.new(pdf_path)
    text_content = reader.pages.map(&:text).join("\n")

    temp_file = Tempfile.new(['pdf_text', '.txt'])
    temp_file.write(text_content[0..50_000]) # Limit to 50K chars
    temp_file.close

    Rails.logger.info "[ChartSectionGenerator] PDF converted to text: #{temp_file.path} (#{text_content.length} chars)"
    [temp_file, temp_file.path]
  rescue StandardError => e
    Rails.logger.error "[ChartSectionGenerator] Error converting PDF: #{e.message}"
    [nil, nil]
  end

  # Convert DOCX to text file
  def convert_docx_to_text(docx_path)
    require 'docx'

    Rails.logger.info "[ChartSectionGenerator] Extracting text from DOCX: #{File.basename(docx_path)}"

    doc = Docx::Document.open(docx_path)
    text_content = doc.paragraphs.map(&:text).join("\n")

    temp_file = Tempfile.new(['docx_text', '.txt'])
    temp_file.write(text_content[0..50_000]) # Limit to 50K chars
    temp_file.close

    Rails.logger.info "[ChartSectionGenerator] DOCX converted to text: #{temp_file.path} (#{text_content.length} chars)"
    [temp_file, temp_file.path]
  rescue StandardError => e
    Rails.logger.error "[ChartSectionGenerator] Error converting DOCX: #{e.message}"
    [nil, nil]
  end

  # Convert chart to HTML in YOUR Python format (so frontend doesn't change!)
  def chart_to_html(chart)
    spec = chart.spec

    # Extract chart type and data
    chart_type = spec['type'] || 'bar'
    chart_data = spec['data'] || {}

    <<~HTML
      <div style="margin-bottom: 30px; padding: 20px; border: 1px solid #dee2e6; border-radius: 8px; background: #f8f9fa;">
        <h4>#{chart.title}</h4>
        <p><em>#{chart.prompt}</em></p>
        <div class="chart-placeholder"#{' '}
             data-chart-config='#{chart_data.to_json}'#{' '}
             data-chart-type='#{chart_type}'
             style="background: white; padding: 20px; border-radius: 4px; min-height: 300px;">
        </div>
      </div>
    HTML
  end

  # Error fallback HTML
  def error_chart_html(prompt, error_message)
    <<~HTML
      <div style="margin-bottom: 30px; padding: 20px; border: 1px solid #dc3545; border-radius: 8px; background: #f8d7da;">
        <h4>?? Chart Generation Failed</h4>
        <p><em>#{prompt}</em></p>
        <p style="color: #721c24;">Error: #{error_message}</p>
      </div>
    HTML
  end

  # Find CSV documents for this portfolio company
  # Find relevant documents (CSV, TXT, MD, PDF, DOCX, XLSX, PPTX) for this portfolio company
  # Find relevant documents from demo_documents folder (like Python backend)
  def find_csv_documents
    document_paths = []

    # Supported file types for chart generation
    supported_extensions = ['.csv', '.txt', '.md', '.pdf', '.docx', '.doc', '.xlsx', '.xls', '.pptx', '.ppt']

    Rails.logger.info "=== Searching for documents ==="

    # Use same path as GenerateSectionContentJob
    demo_docs_path = Pathname.new('/tmp/test_documents')

    if demo_docs_path.exist?
      Rails.logger.info "Checking folder: #{demo_docs_path}"

      supported_extensions.each do |ext|
        Dir.glob(demo_docs_path.join("*#{ext}")).each do |file_path|
          document_paths << file_path
          Rails.logger.info "  ? Found: #{File.basename(file_path)}"
        end
      end
    else
      Rails.logger.warn "demo_documents folder not found at: #{demo_docs_path}"
      Rails.logger.info "Creating demo_documents folder..."
      FileUtils.mkdir_p(demo_docs_path)
    end

    Rails.logger.info "Total documents found: #{document_paths.count}"
    document_paths
  end

  # Extract a preview of data from documents for LLM analysis
  def extract_data_preview(document_paths)
    preview_parts = []

    document_paths.each do |file_path|
      extension = File.extname(file_path).downcase
      filename = File.basename(file_path)

      begin
        case extension
        when '.xlsx', '.xls'
          preview_parts << extract_excel_preview(file_path, filename)
        when '.pptx', '.ppt'
          preview_parts << extract_pptx_preview(file_path, filename)
        when '.csv'
          preview_parts << extract_csv_preview(file_path, filename)
        when '.pdf'
          preview_parts << extract_pdf_preview(file_path, filename)
        when '.docx', '.doc'
          preview_parts << extract_docx_preview(file_path, filename)
        end
      rescue StandardError => e
        Rails.logger.warn "[ChartSectionGenerator] Could not extract preview from #{filename}: #{e.message}"
      end
    end

    preview_parts.compact.join("\n\n")
  end

  # Extract preview from Excel file
  def extract_excel_preview(file_path, filename)
    require 'roo'

    spreadsheet = Roo::Spreadsheet.open(file_path)
    preview = "=== Data from: #{filename} ===\n"

    spreadsheet.sheets.first(3).each do |sheet_name|
      sheet = spreadsheet.sheet(sheet_name)
      preview += "Sheet: #{sheet_name}\n"

      rows = []
      sheet.each_row_streaming(pad_cells: true, max_rows: 200) do |row|
        row_values = row.map { |cell| cell&.value.to_s.strip }.compact_blank
        rows << row_values.join(" | ") if row_values.any?
      end

      preview += "#{rows.join("\n")}\n"
    end

    preview
  end

  # Extract preview from PPTX charts
  def extract_pptx_preview(file_path, filename)
    require 'zip'
    require 'nokogiri'

    preview = "=== Chart Data from: #{filename} ===\n"

    Zip::File.open(file_path) do |zip_file|
      chart_entries = zip_file.glob('ppt/charts/chart*.xml')

      chart_entries.first(5).each_with_index do |entry, idx|
        chart_content = entry.get_input_stream.read
        chart_doc = Nokogiri::XML(chart_content)
        chart_doc.remove_namespaces!

        title = chart_doc.xpath('//title//t').map(&:text).join(' ')
        preview += "\nChart #{idx + 1}: #{title}\n" if title.present?

        chart_doc.xpath('//ser').each do |series|
          series_name = series.xpath('.//tx//v | .//tx//t').first&.text || 'Series'
          categories = series.xpath('.//cat//v | .//cat//t').map(&:text).first(10)
          values = series.xpath('.//val//v').map(&:text).first(10)

          preview += "  #{series_name}: "
          if categories.any? && values.any?
            preview += categories.zip(values).map { |c, v| "#{c}=#{v}" }.join(", ")
          elsif values.any?
            preview += values.join(", ")
          end
          preview += "\n"
        end
      end
    end

    preview
  end

  # Extract preview from CSV file
  def extract_csv_preview(file_path, filename)
    require 'csv'

    preview = "=== Data from: #{filename} ===\n"
    rows = CSV.read(file_path, headers: false).first(20)
    rows.each do |row|
      preview += "#{row.compact.join(' | ')}\n"
    end

    preview
  rescue StandardError => e
    "=== Data from: #{filename} ===\nError reading CSV: #{e.message}"
  end

  def extract_pdf_preview(file_path, filename)
    require 'pdf-reader'

    preview = "=== Data from: #{filename} ===\n"
    reader = PDF::Reader.new(file_path)
    text_content = reader.pages.first(200).map(&:text).join("\n")
    preview += text_content[0..100_000] # Limit to 4000 chars for preview

    preview
  rescue StandardError => e
    "=== Data from: #{filename} ===\nError reading PDF: #{e.message}"
  end

  # Extract preview from DOCX file
  def extract_docx_preview(file_path, filename)
    require 'docx'

    preview = "=== Data from: #{filename} ===\n"
    doc = Docx::Document.open(file_path)
    text_content = doc.paragraphs.first(500).map(&:text).join("\n")
    preview += text_content[0..100_000] # Limit to 4000 chars for preview

    preview
  rescue StandardError => e
    "=== Data from: #{filename} ===\nError reading DOCX: #{e.message}"
  end

  # Generate chart prompts dynamically based on actual data
  def generate_chart_prompts_from_data(data_preview)
    return default_chart_prompts if data_preview.blank?

    Rails.logger.info "[ChartSectionGenerator] Generating chart prompts from data..."

    chat = RubyLLM.chat(model: ENV.fetch("DEFAULT_MODEL", nil))

    prompt = <<~PROMPT
      Analyze the following data and suggest 3 meaningful charts that would visualize key insights.

      DATA:
      #{data_preview[0..4000]}

      For each chart, provide a specific prompt that describes:
      1. What data to visualize
      2. The chart type (line, bar, pie, doughnut)
      3. What insight it should convey

      Return ONLY a JSON array of 3 chart prompts, like:
      ["Revenue trend over time - show monthly revenue as a line chart", "Orders by category - show as a bar chart", "GMV distribution - show as a pie chart"]

      Focus on the actual metrics and data columns present in the data. Be specific about the data fields to use.
    PROMPT

    response = chat.ask(prompt) # llm.complete(prompt: prompt)
    result = response.content.strip

    # Parse JSON array from response
    result = result.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
    prompts = JSON.parse(result)

    Rails.logger.info "[ChartSectionGenerator] LLM generated prompts: #{prompts.inspect}"

    prompts.is_a?(Array) && prompts.length.positive? ? prompts : default_chart_prompts
  rescue StandardError => e
    Rails.logger.error "[ChartSectionGenerator] Error generating prompts: #{e.message}"
    default_chart_prompts
  end

  # Fallback default prompts
  def default_chart_prompts
    [
      "Show key metrics trend over time as a line chart",
      "Show category breakdown as a bar chart",
      "Show distribution as a pie chart"
    ]
  end

  # Extract text content from different document types
  def extract_text_from_document(doc, extension)
    case extension
    when '.pdf'
      # Extract text from PDF
      require 'pdf-reader'
      reader = PDF::Reader.new(StringIO.new(doc.file.download))
      reader.pages.map(&:text).join("\n")

    when '.docx', '.doc'
      # Extract text from Word document
      require 'docx'
      temp_file = Tempfile.new(['doc', extension])
      temp_file.binmode
      temp_file.write(doc.file.download)
      temp_file.close

      docx = Docx::Document.open(temp_file.path)
      text = docx.paragraphs.map(&:text).join("\n")
      temp_file.unlink
      text

    else
      # Fallback for .txt, .md, and other text-based formats
      doc.file.download.to_s
    end
  rescue StandardError => e
    Rails.logger.error "Failed to extract text from #{extension}: #{e.message}"
    "[Document content could not be extracted]"
  end

  # Extract a short title from the prompt
  def extract_title(prompt)
    # Take first part before dash or hyphen
    # Handle if prompt is a Hash (from Gemini response)
    prompt_str = prompt.is_a?(Hash) ? (prompt['prompt'] || prompt[:prompt] || prompt.to_s) : prompt.to_s
    # Take first part before dash or hyphen
    title = prompt_str.split('-').first.to_s.strip
    # Limit to 50 characters
    title.truncate(50)
  end
end
# rubocop:enable Metrics/ClassLength
