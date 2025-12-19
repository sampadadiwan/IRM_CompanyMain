class PortfolioReportAgent < SupportAgentService
  step :initialize_agent
  step :load_document_context
  step :load_web_search_context # NEW: Load web search results
  step :load_section_template
  step :determine_action
  step :generate_or_refine
  step :save_section

  private

  # Initialize agent
  def initialize_agent(ctx, **)
    @support_agent = SupportAgent.find(ctx[:support_agent_id])
    ctx[:support_agent] = @support_agent
  end

  # Clean markdown artifacts from LLM output
  def clean_llm_output(content)
    return "" if content.blank?

    content = content.dup

    # Remove markdown code fences
    content.gsub!(/```html\n?/, '')
    content.gsub!(/```\n?/, '')

    # Remove common markdown artifacts
    content.gsub!(/^html\n/, '')

    # Remove leading/trailing whitespace
    content.strip!

    content
  end

  def load_document_context(ctx, **)
    # Check if cached documents context was passed (optimization: load once, use many times)
    cached_context = ctx[:cached_documents_context]

    if cached_context.present?
      Rails.logger.info "[PortfolioReportAgent] Using cached documents context (#{cached_context.length} chars)"
      ctx[:documents_context] = cached_context
      return true
    end

    # Fallback: load from folder if no cached context
    folder_path = ctx[:document_folder_path]

    if folder_path.blank?
      Rails.logger.info "[PortfolioReportAgent] No document folder path provided"
      ctx[:documents_context] = ""
      return true
    end

    Rails.logger.info "[PortfolioReportAgent] Loading documents from: #{folder_path}"

    begin
      documents_context = load_documents_from_folder(folder_path)
      ctx[:documents_context] = documents_context

      doc_count = documents_context.present? ? documents_context.scan('=== Document:').count : 0
      Rails.logger.info "[PortfolioReportAgent] Loaded #{doc_count} documents"
    rescue StandardError => e
      Rails.logger.error "[PortfolioReportAgent] Error loading documents: #{e.message}"
      ctx[:documents_context] = ""
    end

    true
  end

  def load_web_search_context(ctx, target:, web_search_enabled: false, **)
    ctx[:web_search_enabled] = web_search_enabled
    ctx[:web_search_context] = ""

    Rails.logger.info "[PortfolioReportAgent] Web search enabled in : #{web_search_enabled}"
    return true unless web_search_enabled

    section = target
    report = section.ai_portfolio_report
    company_name = report.portfolio_company&.name

    return true unless company_name.present?

    Rails.logger.info "[PortfolioReportAgent] Web search enabled - searching for #{company_name}"

    begin
      queries = build_search_queries(section.section_type, company_name)
      Rails.logger.info "[PortfolioReportAgent] Executing #{queries.count} web searches..."

      search_results = []
      # Use threads to execute searches in parallel to avoid timeout
      threads = queries.map do |query|
        Thread.new do
          Rails.logger.info "[PortfolioReportAgent] Starting search for: #{query}"
          result = AgentTools::WebSearchTool.search(query)
          formatted = format_search_result(query, result) unless result[:error]
          Rails.logger.info "[PortfolioReportAgent] Finished search for: #{query}"
          formatted
        end
      end

      threads.each do |t|
        res = t.value
        search_results << res if res.present?
      end

      ctx[:web_search_context] = search_results.join("\n\n")

      Rails.logger.info "[PortfolioReportAgent] Loaded #{search_results.count} web search results"
      true
    rescue StandardError => e
      Rails.logger.error "[PortfolioReportAgent] Web search error: #{e.message}"
      ctx[:web_search_context] = ""
      true
    end
  end

  # Load section-specific template
  def load_section_template(ctx, target:, **)
    section = target

    ctx[:section] = section
    ctx[:section_type] = section.section_type
    ctx[:template] = get_section_template(section.section_type)

    Rails.logger.info "[PortfolioReportAgent] section_type: #{section.section_type}"
    Rails.logger.info "[PortfolioReportAgent] STEP 4: load_section_template END"

    Rails.logger.info "[PortfolioReportAgent] Processing: #{section.section_type}"

    true
  end

  def determine_action(ctx, action: 'generate', web_search_enabled: false, **)
    ctx[:action] = action
    ctx[:user_prompt] = ctx[:user_prompt] || ""
    ctx[:current_content] = ctx[:current_content] || ""
    ctx[:web_search_enabled] = web_search_enabled

    Rails.logger.info "[PortfolioReportAgent] Action: #{action}"
    Rails.logger.info "[PortfolioReportAgent] Web search: #{web_search_enabled}"

    true
  end

  # Generate OR refine based on action
  def generate_or_refine(ctx, **)
    if ctx[:action] == 'refine' && ctx[:current_content].present?
      refine_section_content(ctx)
    else
      generate_section_content(ctx)
    end
    true
  end

  # Generate section content using LLM
  def generate_section_content(ctx, **)
    section_type = ctx[:section_type]
    template = ctx[:template]
    documents = ctx[:documents_context]
    web_search = ctx[:web_search_context]
    section = ctx[:section]

    Rails.logger.info "[PortfolioReportAgent] ===== GENERATE SECTION CONTENT ====="
    Rails.logger.info "[PortfolioReportAgent] Section type: #{section_type}"
    Rails.logger.info "[PortfolioReportAgent] Web Search Enabled: #{ctx[:web_search_enabled]}"
    Rails.logger.info "[PortfolioReportAgent] Web Search Context Present: #{web_search.present?}"
    Rails.logger.info "[PortfolioReportAgent] Documents context length: #{documents&.length || 0}"
    Rails.logger.info "[PortfolioReportAgent] Documents context preview (first 1000 chars): #{documents&.[](0..1000).inspect}"
    Rails.logger.info "[PortfolioReportAgent] Web search context length: #{web_search&.length || 0}"

    report = section.ai_portfolio_report
    company = report.portfolio_company

    # Build prompt
    prompt = build_generation_prompt(
      section_type: section_type,
      template: template,
      documents: documents,
      web_search: web_search,
      company_name: company.name,
      report_date: report.report_date
    )

    Rails.logger.info "[PortfolioReportAgent] Full prompt length: #{prompt.length}"
    Rails.logger.info "[PortfolioReportAgent] Full prompt (first 2000 chars): #{prompt[0..2000].inspect}"

    # # Call LLM
    # api_key = ENV.fetch('OPENAI_API_KEY', nil)
    # raise "OpenAI API key not found" unless api_key

    # llm = Langchain::LLM::OpenAI.new(
    #   api_key: api_key,
    #   default_options: {
    #     chat_completion_model_name: ENV['REPORT_AGENT_MODEL'] || 'gpt-4o',
    #     temperature: 0.3
    #   }
    # )

    # Rails.logger.info "[PortfolioReportAgent] Calling LLM to generate content..."

    # response = llm.complete(prompt: prompt)
    # content = clean_llm_output(response.completion)

    # Call LLM using RubyLLM
    Rails.logger.info "[PortfolioReportAgent] Calling LLM to generate content..."

    chat = RubyLLM.chat(model: 'gemini-2.5-pro')
    response = chat.ask(prompt)
    content = clean_llm_output(response.content)

    ctx[:generated_content] = content

    Rails.logger.info "[PortfolioReportAgent] Generated #{content.length} characters"

    true
  end

  # Refine existing content
  def refine_section_content(ctx, **)
    section_type = ctx[:section_type]
    documents = ctx[:documents_context]
    web_search = ctx[:web_search_context]
    current_content = ctx[:current_content]
    user_prompt = ctx[:user_prompt]
    web_search_enabled = ctx[:web_search_enabled]
    section = ctx[:section]

    report = section.ai_portfolio_report
    company = report.portfolio_company

    Rails.logger.info "[PortfolioReportAgent] ===== REFINE SECTION CONTENT ====="
    Rails.logger.info "[PortfolioReportAgent] Web Search Enabled: #{web_search_enabled}"
    Rails.logger.info "[PortfolioReportAgent] Web Search Context Present: #{web_search.present?}"

    # Build refinement prompt
    prompt = build_refinement_prompt(
      section_type: section_type,
      current_content: current_content,
      user_prompt: user_prompt,
      documents: documents,
      web_search: web_search,
      company_name: company.name,
      web_search_enabled: web_search_enabled
    )

    # # Call LLM
    # api_key = ENV.fetch('OPENAI_API_KEY', nil)
    # raise "OpenAI API key not found" unless api_key

    # llm = Langchain::LLM::OpenAI.new(
    #   api_key: api_key,
    #   default_options: {
    #     chat_completion_model_name: ENV['REPORT_AGENT_MODEL'] || 'gpt-4o',
    #     temperature: 0.7
    #   }
    # )

    # Rails.logger.info "[PortfolioReportAgent] Calling LLM to refine content..."

    # response = llm.complete(prompt: prompt)
    # content = clean_llm_output(response.completion)
    #
    # Call LLM using RubyLLM
    Rails.logger.info "[PortfolioReportAgent] Calling LLM to refine content..."

    chat = RubyLLM.chat(model: 'gemini-2.5-pro')
    response = chat.ask(prompt)
    content = clean_llm_output(response.content)

    ctx[:generated_content] = content

    Rails.logger.info "[PortfolioReportAgent] Refined #{content.length} characters"
    true
  end

  # Save section to database
  def save_section(ctx, section:, generated_content:, **)
    web_search_enabled = ctx[:web_search_enabled] || false

    # Save to appropriate column and update timestamps
    if web_search_enabled
      update_attrs = {
        content_html_with_web: generated_content,
        updated_at_web_included: Time.current,
        reviewed: false
      }
      # Set created_at only on first web search generation
      update_attrs[:created_at_web_included] = Time.current if section.created_at_web_included.blank?
    else
      update_attrs = {
        content_html: generated_content,
        updated_at_document_only: Time.current,
        reviewed: false
      }
      # Set created_at only on first document generation
      update_attrs[:created_at_document_only] = Time.current if section.created_at_document_only.blank?
    end

    section.update!(update_attrs)

    Rails.logger.info "[PortfolioReportAgent] Section saved (web_search: #{web_search_enabled})"

    ctx[:section_id] = section.id

    true
  end

  # == Helper Methods ==

  # Get section-specific template
  def get_section_template(section_type)
    templates = {
      "Company Overview" => {
        description: "A sharp, investment-grade overview describing the company’s sector, problem statement, product focus, and founder details.",
        structure: [
          "Identify the sector and precise sub-sector (D2C, fintech, SaaS, etc.)",
          "State the core customer problem the company solves in one crisp line",
          "Describe key product lines and/or business model with clarity",
          "Include founding year, founder name, and 1-2 key background highlights",
          "Highlight what makes the company differentiated (USP, model, tech, distribution)"
        ],
        length: "1 strong paragraph plus 3-5 high-impact bullet points"
      },
      "Key Products & Services" => {
        description: "Clear articulation of the company’s major products, revenue drivers, business model structure, and distribution channels.",
        structure: [
          "List core product categories and sub-categories",
          "Describe revenue model (D2C, marketplace, subscription, enterprise, etc.)",
          "Highlight product or service differentiators (tech, ingredients, IP, supply chain, pricing)",
          "Refer to any charts generated from Excel to support explanation where relevant",
          "Mention customer segments and top use cases"
        ],
        length: "4-6 sharp bullet points plus an optional short paragraph summary"
      },
      "Financial Snapshot" => {
        description: "Data-driven summary of the company’s financial performance using uploaded spreadsheets and dashboard KPIs.",
        structure: [
          "Summarize revenue growth patterns (Y/Y, Q/Q, M/M as available)",
          "Describe profitability or burn profile (EBITDA, margins, cash burn)",
          "Comment on working capital, CAC, payback, or other available metrics",
          "Highlight trends with charts (revenue vs time, margin trends, burn/runway, etc.)",
          "Include 3-5 insightful interpretation lines, not just a repeat of numbers"
        ],
        length: "1 paragraph plus at least 1 chart reference and 3-4 analytical bullet points"
      },
      "Market Size & Target" => {
        description: "Clearly defined TAM, SAM, and SOM with supporting market logic and numerical justification.",
        structure: [
          "Give a concise contextual definition of the broader sector",
          "Provide latest TAM, SAM, SOM values based on documents and/or web search",
          "Show the computation in a small table (TAM, SAM, SOM, and values)",
          "State why the market timing is attractive (macro trends, digital adoption, etc.)",
          "Include 2-3 competitive or macro tailwinds relevant to the company"
        ],
        length: "1 paragraph plus a 3-row table and 3 concise bullets"
      },
      "Recent Updates & Developments" => {
        description: "Crisp summary of the latest noteworthy events extracted from uploaded documents and optionally web search.",
        structure: [
          "Product launches or enhancements",
          "Partnerships, distribution expansions, or key customer wins",
          "Hiring of senior leadership or critical team changes",
          "Operational or financial milestones in the last 1-4 quarters",
          "Keep items factual, time-stamped where possible, and concise"
        ],
        length: "5-7 bullet points"
      },
      "Custom Charts" => {
        description: "Generate and interpret insightful charts based on user-chosen parameters (cash burn, runway, revenue trends, industry metrics, etc.).",
        structure: [
          "Identify which metric combinations make most sense for this company and industry",
          "Describe the chart(s) to be generated from provided Excel/CSV (axes, metrics, timeframe)",
          "Provide 3-4 lines of interpretation explaining what the chart shows and why it matters",
          "Optionally suggest additional charts that an analyst may want to explore next"
        ],
        length: "Chart description plus 3-4 analytical bullets"
      },
      "Founders & Shareholders" => {
        description: "Concise founder biography plus cap table and investor quality insights.",
        structure: [
          "Summarize founder’s education and 2-3 relevant past experiences",
          "Highlight domain expertise or technology/scale-up capabilities",
          "Describe founder-led strengths (distribution, product, brand building, etc.)",
          "Summarize key shareholders (VCs, angels, strategics) and any notable names",
          "Explain briefly why this founder and cap table are well aligned with the opportunity"
        ],
        length: "1 paragraph plus 3-4 bullet points"
      },
      "Raise History, Valuations & Funding trend" => {
        description: "Timeline of funding with insights on valuation trajectory, investor quality, and capital deployment.",
        structure: [
          "Provide a tabular history of all funding rounds with date, round, raise amount, and valuation",
          "Comment on valuation growth trend and any inflection points",
          "Highlight marquee investors and their relevance to the company and sector",
          "Mention how capital has likely been deployed (product, marketing, team, expansion, etc.)",
          "Add 2-3 forward-looking insights on runway implications and future capital needs"
        ],
        length: "1 table plus 4-5 bullet points of commentary"
      },
      "SWOT Analysis - Blitz" => {
        description: "Comprehensive SWOT analysis rooted in sector realities and company-specific data.",
        structure: [
          "Strengths: 6-10 points on brand, tech, distribution, margins, community, etc.",
          "Weaknesses: 6-10 points on dependencies, recall, CAC, concentration, etc.",
          "Opportunities: 6-10 points on market growth, new segments, new geos, new channels, etc.",
          "Threats: 6-10 points on regulation, competition, churn, raw material, macro, etc."
        ],
        length: "Four quadrants with 6-10 points each"
      },
      "Competition Analysis" => {
        description: "Position the company relative to market alternatives in a structured, analytical manner.",
        structure: [
          "Describe overall competitive landscape (incumbents, D2C challengers, premium/clinical players, etc.)",
          "Identify where this company sits on price point, brand voice, tech, and formulation/feature set",
          "Highlight clear USPs (for example, Ayurveda plus science plus personalization, or similar)",
          "Discuss customer perception and loyalty vs key competitors",
          "Conclude with 2-3 lines on sustainable edge or lack thereof"
        ],
        length: "1-2 tight paragraphs plus 3 key differentiator bullets"
      },
      "Key Risks" => {
        description: "Highlight investor-relevant risks with clear reasoning and potential business impact.",
        structure: [
          "Market risks (competition intensity, category maturity, customer behavior changes)",
          "Operational risks (supply chain, logistics, manufacturing, R&D limitations)",
          "Financial risks (CAC creep, burn rate, dependence on external funding)",
          "Regulatory risks (labeling, data/privacy, sector-specific compliance requirements)",
          "Each risk should include cause plus potential impact and a hint of mitigation where visible"
        ],
        length: "4-6 bullet points with 2 lines of explanation each"
      },
      "Operational Red Flags" => {
        description: "Identify execution risks and operational fragilities based on documents and industry norms.",
        structure: [
          "Supply chain dependencies and single points of failure",
          "Quality control gaps or lack of robust testing/QA",
          "Inventory or demand planning risks (stockouts, overstock, seasonality)",
          "Customer service, fulfilment, and logistics-related weaknesses",
          "Tech, data, or process reliability concerns that may not yet be visible in financials"
        ],
        length: "4-6 concise bullet points"
      },
      "Negative News" => {
        description: "Summarize negative press, regulatory actions, controversies, or customer concerns impacting the company.",
        structure: [
          "Potential controversies related to product claims, ingredients, or safety",
          "Regulatory tightening risks or any known notices/warnings",
          "Consumer complaints, rating downgrades, or social media criticism patterns",
          "Brand reputation vulnerabilities and how quickly sentiment can turn"
        ],
        length: "3-5 bullet points"
      },
      "AML/KYB Check" => {
        description: "Perform a structured compliance and background screening summary using AML/KYB data.",
        structure: [
          "Verify legal entity details and jurisdiction of incorporation",
          "Summarize checks for sanctions, watchlists, and adverse media hits (if any)",
          "Mention any historical red flags, legal disputes, or compliance gaps identified",
          "Provide a simple qualitative risk rating (Low, Medium, or High) with justification"
        ],
        length: "Short compliance summary of 1 paragraph plus 2-3 bullets if needed"
      },
      "Investment Ask" => {
        description: "Summarize funding ask, valuation, and capital deployment rationale in an investor-ready way.",
        structure: [
          "State the amount being raised, currency, and valuation (pre or post-money)",
          "Break down planned use of funds (customer acquisition, product development, team, expansion, etc.)",
          "Explain how this capital will move core metrics (revenue, runway, profitability, market share)",
          "Close with 1-2 lines on why this is the right moment for investors to participate"
        ],
        length: "1 compact paragraph plus 3-4 bullet points"
      }
    }

    templates[section_type] || {
      description: "Investor-grade analysis and insights for #{section_type}, grounded in the uploaded documents and, where allowed, web search.",
      structure: [
        "Define what this section should cover in the context of a portfolio company",
        "Summarize key quantitative and qualitative insights",
        "Explain implications for investors (upside, risks, and watchpoints)"
      ],
      length: "1-2 short paragraphs or 3-5 bullet points"
    }
  end

  def build_generation_prompt(section_type:, template:, documents:, company_name:, report_date:, web_search: "")
    <<~PROMPT
      You are a professional investment analyst creating a #{section_type} section for a portfolio company report.

      Company name must be inferred from documents if present

      Report Date: #{report_date}

      #{"AVAILABLE DOCUMENTS:\n#{documents}\n" if documents.present?}

      #{"LATEST WEB SEARCH RESULTS:\n#{web_search}\n" if web_search.present?}

      SECTION REQUIREMENTS:
      Description: #{template[:description]}
      Structure: #{template[:structure].join(', ')}
      Length: #{template[:length]}

      CRITICAL - OUTPUT FORMAT:
      - Return ONLY HTML content (no markdown)
      - DO NOT wrap output in code blocks or backticks
      - DO NOT include ```html or ``` markers
      - Use proper HTML tags: <h2>, <h3>, <p>, <ul>, <li>, <strong>, <em>
      - Start directly with HTML tags (e.g., <h2>Section Title</h2>)
      - End with closing HTML tags (no extra text after)
      - If documents are provided, DO NOT rely on any externally provided company name
      - Identify and use the company name ONLY if explicitly mentioned in the documents
      - If multiple or conflicting company names appear, state "Multiple companies referenced in provided documents"
      - If no company name is mentioned, use "Company (name not specified in documents)"

      INSTRUCTIONS:
      1. Write in professional, analytical tone
      2. Format in HTML (NOT markdown)
      3. Include relevant metrics and numbers from the documents
      #{if documents.present?
          <<~DOC_RULES
            CRITICAL - SOURCE RESTRICTIONS:
            - ONLY use information explicitly stated in the provided documents
            - DO NOT add any facts, figures, or claims not found in the documents
            - DO NOT use your general knowledge about the company or industry
            - If information for a required section is missing from documents, write "Information not available in provided documents"
            - Every claim must be traceable to the document content above
          DOC_RULES
        else
          '4. Use general industry knowledge since no documents are provided'
        end}
      #{'- You may also incorporate facts from the web search results provided above' if web_search.present?}

      Generate the #{section_type} section now in pure HTML format (no code blocks):
    PROMPT
  end

  # Refinement prompt
  def build_refinement_prompt(section_type:, current_content:, user_prompt:, documents:, company_name:, web_search: "", web_search_enabled: false)
    <<~PROMPT
      You are a professional investment analyst refining a #{section_type} section for a portfolio company report.

      Company name must be inferred from documents if present

      CURRENT CONTENT (HTML):
      #{current_content}

      USER REQUEST (treat as refinement instruction, not a question):
      #{user_prompt}

      #{"AVAILABLE DOCUMENTS FOR REFERENCE:\n#{documents}\n" if documents.present?}

      #{"LATEST WEB SEARCH RESULTS:\n#{web_search}\n" if web_search.present?}

      CRITICAL - OUTPUT FORMAT:
      - Return ONLY HTML content (no markdown, no code blocks)
      - Use proper HTML tags: <h2>, <h3>, <p>, <ul>, <li>, <strong>, <em>
      - Maintain professional formatting

      INSTRUCTIONS:
      1. Carefully read the current content and user request
      2. Apply the requested changes while maintaining professional quality
      3. Preserve important information unless asked to remove it
      4. Adjust tone, length, or focus as requested
      #{if documents.present?
          <<~DOC_RULES
            CRITICAL - SOURCE RESTRICTIONS:
            - ONLY use information from the provided documents or current content
            - DO NOT add any facts, figures, or claims not found in documents
            - DO NOT use your general knowledge about the company or industry
            - If user requests information not in documents, state "Information not available in provided documents"
            - If documents are provided, DO NOT rely on any externally provided company name
            - Identify and use the company name ONLY if explicitly mentioned in the documents
            - If multiple or conflicting company names appear, state "Multiple companies referenced in provided documents"
            - If no company name is mentioned, use "Company (name not specified in documents)"

          DOC_RULES
        end}
      #{'- You may also incorporate facts from the web search results provided above' if web_search.present?}

      Refine the content according to the user's request now:
    PROMPT
  end

  # Load documents from folder
  def load_documents_from_folder(folder_path)
    return "" unless folder_path.present? && Dir.exist?(folder_path)

    documents = []
    supported_extensions = %w[.pdf .txt .md .docx .xlsx .xls .pptx .ppt]

    Dir.glob(File.join(folder_path, "*")).each do |file_path|
      next unless File.file?(file_path)

      extension = File.extname(file_path).downcase
      next unless supported_extensions.include?(extension)

      begin
        text = extract_text_from_file(file_path, extension)

        documents << {
          name: File.basename(file_path),
          content: text[0..5000]
        }

        break if documents.count >= 10
      rescue StandardError => e
        Rails.logger.warn "[PortfolioReportAgent] Could not extract: #{file_path}"
      end
    end

    format_documents_for_llm(documents)
  end

  # Extract text from file
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

  # Extract PDF text
  def extract_pdf_text(file_path)
    require 'pdf-reader'

    reader = PDF::Reader.new(file_path)
    text = reader.pages.first(20).map(&:text)

    text.join("\n\n")
  rescue StandardError => e
    "Error extracting PDF: #{e.message}"
  end

  # Extract Excel text using roo gem
  def extract_excel_text(file_path)
    require 'roo'

    spreadsheet = Roo::Spreadsheet.open(file_path)
    text_parts = []

    spreadsheet.sheets.first(5).each do |sheet_name|
      sheet = spreadsheet.sheet(sheet_name)
      text_parts << "=== Sheet: #{sheet_name} ==="

      # Get all rows from the sheet
      rows = []
      sheet.each_row_streaming(pad_cells: true, max_rows: 100) do |row|
        row_values = row.map { |cell| cell&.value.to_s.strip }.reject(&:blank?)
        rows << row_values.join(" | ") if row_values.any?
      end

      text_parts << rows.join("\n")
    end

    text_parts.join("\n\n")
  rescue StandardError => e
    Rails.logger.error "[PortfolioReportAgent] Error extracting Excel: #{e.message}"
    "Error extracting Excel: #{e.message}"
  end

  # Extract PowerPoint text using zip and XML parsing
  def extract_pptx_text(file_path)
    require 'zip'
    require 'nokogiri'

    Rails.logger.info "[PortfolioReportAgent] PPTX Extraction START for: #{file_path}"

    text_parts = []
    slide_number = 0

    Zip::File.open(file_path) do |zip_file|
      # Find all slide XML files
      slide_entries = zip_file.glob('ppt/slides/slide*.xml').sort_by do |entry|
        entry.name.match(/slide(\d+)\.xml/)[1].to_i
      end

      Rails.logger.info "[PortfolioReportAgent] PPTX: Found #{slide_entries.count} slides"

      slide_entries.first(30).each do |entry|
        slide_number += 1
        content = entry.get_input_stream.read
        doc = Nokogiri::XML(content)
        doc.remove_namespaces!

        # Extract all text content from the slide
        texts = doc.xpath('//t').map(&:text).reject(&:blank?)

        Rails.logger.info "[PortfolioReportAgent] PPTX Slide #{slide_number}: #{texts.count} text elements"
        Rails.logger.info "[PortfolioReportAgent] PPTX Slide #{slide_number} text: #{texts.first(5).join(' | ')}" if texts.any?

        if texts.any?
          text_parts << "=== Slide #{slide_number} ==="
          text_parts << texts.join("\n")
        end
      end

      # Also extract chart data which often contains important numeric information
      chart_entries = zip_file.glob('ppt/charts/chart*.xml')
      Rails.logger.info "[PortfolioReportAgent] PPTX: Found #{chart_entries.count} charts"

      chart_entries.first(10).each_with_index do |entry, idx|
        chart_content = entry.get_input_stream.read
        chart_doc = Nokogiri::XML(chart_content)
        chart_doc.remove_namespaces!

        # Extract series names and values from charts
        chart_data = extract_chart_data(chart_doc)
        next unless chart_data.present?

        Rails.logger.info "[PortfolioReportAgent] PPTX Chart #{idx + 1}: #{chart_data.length} chars extracted"
        Rails.logger.info "[PortfolioReportAgent] PPTX Chart #{idx + 1} preview: #{chart_data[0..200]}"
        text_parts << "=== Chart #{idx + 1} Data ==="
        text_parts << chart_data
      end
    end

    Rails.logger.info "[PortfolioReportAgent] PPTX text_parts count: #{text_parts.count}"
    Rails.logger.info "[PortfolioReportAgent] PPTX text_parts first 3: #{text_parts.first(3).inspect}"

    result = text_parts.join("\n\n")
    Rails.logger.info "[PortfolioReportAgent] PPTX Extraction COMPLETE: #{result.length} total chars"
    Rails.logger.info "[PortfolioReportAgent] PPTX Full extracted text (first 500 chars): #{result[0..500].inspect}"
    Rails.logger.info "[PortfolioReportAgent] PPTX Full extracted text (500-1000 chars): #{result[500..1000].inspect}"

    result.presence || "No text content found in PowerPoint"
  rescue StandardError => e
    Rails.logger.error "[PortfolioReportAgent] Error extracting PPTX: #{e.message}"
    Rails.logger.error "[PortfolioReportAgent] PPTX Error backtrace: #{e.backtrace.first(5).join("\n")}"
    "Error extracting PPTX: #{e.message}"
  end

  # Extract data from chart XML
  def extract_chart_data(chart_doc)
    data_parts = []

    # Get chart title if present
    title = chart_doc.xpath('//title//t').map(&:text).join(' ')
    data_parts << "Title: #{title}" if title.present?

    # Extract series data (labels and values)
    chart_doc.xpath('//ser').each do |series|
      series_name = series.xpath('.//tx//v | .//tx//t').first&.text
      data_parts << "Series: #{series_name}" if series_name.present?

      # Get category labels
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

  # Format documents for LLM
  def format_documents_for_llm(documents)
    return "No documents available." if documents.empty?

    formatted = documents.map do |doc|
      "=== Document: #{doc[:name]} ===\n#{doc[:content]}\n"
    end

    formatted.join("\n---\n\n")
  end

  # NEW: Build search queries based on section type
  def build_search_queries(section_type, company_name)
    base_query = company_name

    queries = case section_type
              when "Company Overview"
                ["#{base_query} company overview", "#{base_query} business model"]
              when "Market Size & Target"
                ["#{base_query} market size", "#{base_query} target market"]
              when "Recent Updates & Developments"
                ["#{base_query} news", "#{base_query} recent developments"]
              when "Competition Analysis"
                ["#{base_query} competitors", "#{base_query} market position"]
              when "Key Risks"
                ["#{base_query} risks", "#{base_query} challenges"]
              when "Negative News"
                ["#{base_query} controversy", "#{base_query} negative news"]
              else
                ["#{base_query} #{section_type.downcase}"]
              end

    queries.first(2) # Limit to 2 queries to avoid rate limiting
  end

  # NEW: Format search result for prompt
  def format_search_result(query, result)
    return "" if result[:error]

    # Check if we have any meaningful content
    has_content = result[:abstract_text].present? || result[:related_topics].present?

    unless has_content
      Rails.logger.warn "[PortfolioReportAgent] Web search returned no results for: #{query}"
      return ""
    end

    formatted = "=== Web Search: #{query} ===\n"

    if result[:abstract_text].present?
      formatted += "Summary: #{result[:abstract_text]}\n"
      formatted += "Source: #{result[:abstract_source]} (#{result[:abstract_url]})\n" if result[:abstract_source]
    end

    if result[:related_topics].present?
      formatted += "\nRelated Information:\n"
      result[:related_topics].first(3).each do |topic|
        formatted += "- #{topic}\n"
      end
    end

    Rails.logger.info "[PortfolioReportAgent] Web search found content for: #{query} (#{formatted.length} chars)"
    formatted
  end
end
