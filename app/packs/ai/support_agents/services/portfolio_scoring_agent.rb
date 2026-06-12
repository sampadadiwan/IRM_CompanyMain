class PortfolioScoringAgent < SupportAgentService
  DESCRIPTION = "Scores portfolio companies using sector-specific LLM skill prompts uploaded as custom fields.".freeze

  LONG_DESCRIPTION = <<~DESC.freeze
    Scores each portfolio company using sector-specific LLM skill prompts. Uploads documents,
    KPI data, and valuations as context, then asks the LLM to produce a structured investment score.

    Steps:
    • Load Skill — reads the sector-specific skill prompt from the agent's custom fields,
      matched by the portfolio company's sector value.
    • Gather Data — collects documents (PDF, XLSX, PPTX, DOCX, TXT, MD, CSV), KPI reports,
      and valuations for the company.
    • Generate Score — sends all context and the skill prompt to the configured LLM. Expects a
      JSON response with keys: overall_score, grade, summary, dimensions.
    • Store Score — persists the structured score to the investor record and saves a SupportAgentReport.

    Companies without a sector set are skipped — a sector is required to match a skill prompt.
    Batch processing: sequential across all portfolio companies that have a sector.
  DESC

  REQUIRED_SCORE_KEYS = %w[overall_score grade summary dimensions].freeze
  SUPPORTED_DOC_EXTENSIONS = %w[.pdf .txt .md .xlsx .xls .pptx .ppt .docx .doc .csv].freeze

  STEP_LABELS = {
    initialize_agent: "Initialize",
    load_sector_skill: "Load Skill",
    gather_portco_data: "Gather Data",
    generate_score: "Score",
    store_score: "Save Score"
  }.freeze

  step :initialize_agent
  step :load_sector_skill
  step :gather_portco_data
  step :generate_score
  step :store_score

  # Accepts a single Investor (for adhoc/widget runs) or an entity_id (for batch runs).
  # Only includes companies with a sector set — no sector means no skill file can be matched.
  def targets(entity_id)
    if entity_id.is_a?(Investor) || entity_id.is_a?(ActiveRecord::Base)
      [entity_id]
    else
      Investor
        .where(entity_id: entity_id, category: "Portfolio Company")
        .where.not(sector: [nil, ""])
        .includes(:portfolio_kpi_reports, :valuations, :portfolio_investments)
    end
  end

  # Batch processor — shared by adhoc and scheduled runs.
  # Sequential (no threading) so each wtf? call sees a clean context.
  # :scheduled mode suppresses the batch summary email/notification.
  def self.process_batch(support_agent_id:, targets:, user_id:, entity_id:, with_steps: false, execution_mode: :adhoc_batch)
    support_agent = SupportAgent.find(support_agent_id)
    targets = targets.includes(:portfolio_kpi_reports, :valuations, :portfolio_investments, :documents) if targets.respond_to?(:includes)

    successes = []
    errors    = []

    targets.to_a.each do |target|
      support_agent.agent.wtf?(support_agent_id: support_agent_id, target: target, user_id: user_id, entity_id: entity_id, batch_mode: true)
      successes << { id: target.id, name: target.try(:investor_name) || target.try(:name) || "ID=#{target.id}" }
    rescue StandardError => e
      Rails.logger.error { "[PortfolioScoringAgent] process_batch error for Target ID=#{target.id}: #{e.message}" }
      Rails.logger.error { e.backtrace.join("\n") }
      errors << { target_id: target.id, target_name: target.try(:investor_name) || target.try(:name) || "ID=#{target.id}", error: e.message }
    end

    if execution_mode != :scheduled
      begin
        batch_target_type = targets.first.class.name if targets.any?
        SupportAgentJob.new.send(:send_batch_summary, support_agent, successes, errors, user_id, batch_target_type) if defined?(SupportAgentJob)
      rescue StandardError => e
        Rails.logger.error { "[PortfolioScoringAgent] process_batch: failed to send batch summary: #{e.message}" }
      end
    end

    { successes: successes, errors: errors }
  end

  private

  # Loads the investor and support_agent into context.
  def initialize_agent(ctx, target: nil, **)
    super
    investor = target
    ctx[:investor] = investor
    Rails.logger.info { "[PortfolioScoringAgent] Initializing for Investor ID=#{investor.id} sector=#{investor.sector}" }
    investor.category == "Portfolio Company" && @support_agent.enabled?
  end

  # Downloads the skill markdown file for the investor's sector.
  # Always returns true so store_score can persist a failed report on any error path.
  def load_sector_skill(ctx, investor: nil, **)
    sector = investor.sector.to_s.strip
    if sector.blank?
      Rails.logger.warn { "[PortfolioScoringAgent] Investor ID=#{investor.id} has no sector set — skipping" }
      ctx[:skill_error] = "No sector configured on this portfolio company"
      return true
    end

    skill_doc = @support_agent.skill_for_sector(sector)
    unless skill_doc
      Rails.logger.warn { "[PortfolioScoringAgent] No skill configured for sector '#{sector}' on agent ID=#{@support_agent.id}" }
      ctx[:skill_error] = "No skill file configured for sector: #{sector}"
      return true
    end

    skill_content = read_document_text(skill_doc)
    if skill_content.blank?
      ctx[:skill_error] = "Skill file for sector '#{sector}' is empty or could not be read"
      return true
    end

    ctx[:sector]        = sector
    ctx[:skill_content] = skill_content
    Rails.logger.info { "[PortfolioScoringAgent] Loaded skill for sector '#{sector}' (#{skill_content.length} chars)" }
    true
  end

  # Gathers all available structured and unstructured data for the portfolio company.
  # Skips the expensive gather if a skill error was recorded in a prior step.
  def gather_portco_data(ctx, investor: nil, **)
    return true if ctx[:skill_error]

    ctx[:portco_data] = {
      company_name: investor.investor_name,
      sector: investor.sector,
      custom_fields: investor.json_fields.compact_blank,
      kpi_reports: gather_kpi_data(investor),
      portfolio_investments: gather_investment_data(investor),
      valuations: gather_valuation_data(investor),
      documents: gather_document_texts(investor)
    }
    Rails.logger.info { "[PortfolioScoringAgent] Data gathered for #{investor.investor_name}: #{ctx[:portco_data].keys.join(', ')}" }
    true
  end

  # Calls the LLM with the skill prompt + gathered data. Extracts and validates the JSON score.
  # Always returns true so store_score always runs — errors are carried in ctx[:score_error].
  def generate_score(ctx, investor: nil, **)
    return true if ctx[:skill_error]

    prompt = build_scoring_prompt(ctx[:skill_content], ctx[:portco_data])
    Rails.logger.info { "[PortfolioScoringAgent] Sending scoring prompt (#{prompt.length} chars) to LLM for #{investor.investor_name}" }

    response    = ctx[:llm].ask(prompt)
    raw_content = extract_text_content(response)
    score       = extract_score_json(raw_content)

    ctx[:score]     = score
    ctx[:score_raw] = raw_content
    Rails.logger.info { "[PortfolioScoringAgent] Score generated for #{investor.investor_name}: overall=#{score['overall_score']} grade=#{score['grade']}" }
    true
  rescue StandardError => e
    Rails.logger.error { "[PortfolioScoringAgent] LLM scoring failed for Investor ID=#{investor.id}: #{e.message}" }
    ctx[:score_error] = e.message
    true
  end

  # Persists the score as a new SupportAgentReport (history is preserved across runs).
  def store_score(ctx, investor: nil, support_agent: nil, **)
    if ctx[:score]
      report = SupportAgentReport.create!(
        owner: investor,
        support_agent: support_agent,
        status: :completed,
        json_fields: {
          "score" => ctx[:score],
          "sector" => ctx[:sector],
          "final_status" => "ready",
          "run_at" => Time.current.iso8601,
          "completed_at" => Time.current.iso8601
        }
      )
      Rails.logger.info { "[PortfolioScoringAgent] Score stored — SupportAgentReport ID=#{report.id} for Investor ID=#{investor.id}" }
    else
      error_msg = ctx[:skill_error] || ctx[:score_error] || "Unknown scoring error"
      SupportAgentReport.create!(
        owner: investor,
        support_agent: support_agent,
        status: :failed,
        json_fields: {
          "error" => error_msg,
          "sector" => ctx[:sector],
          "final_status" => "failed",
          "run_at" => Time.current.iso8601,
          "completed_at" => Time.current.iso8601
        }
      )
      Rails.logger.warn { "[PortfolioScoringAgent] Score failed for Investor ID=#{investor.id}: #{error_msg}" }
    end
    true
  end

  # --- Data gathering helpers ---

  # Returns approved actuals KPIs only, grouped by their Actual-tagged KPI report.
  # Filtered by `kpi_frequency` agent config (Month/Quarter/Half Year/Year/YTD/All).
  def gather_kpi_data(investor)
    scope = investor.portfolio_kpi_reports
                    .where(tag_list: "Actual")
                    .order(as_of: :desc)
                    .includes(:kpis)

    # Apply period-type filter when configured and not "All"
    freq = @support_agent.json_fields["kpi_frequency"].to_s.strip
    if freq.present? && !freq.casecmp?("all")
      scope = scope.where(period: freq)
      Rails.logger.info { "[PortfolioScoringAgent] kpi_frequency=#{freq} — filtering KPI reports to period='#{freq}'" }
    else
      Rails.logger.info { "[PortfolioScoringAgent] kpi_frequency=#{freq.presence || '(blank)'} — no period filter applied, using all periods" }
    end

    results = scope.filter_map do |report|
      approved_kpis = report.kpis.approved.map { |k| { name: k.name, value: k.value, denomination: k.investor_kpi_mapping&.denomination }.compact }
      next if approved_kpis.empty?

      { period: report.period, as_of: report.as_of, kpis: approved_kpis }
    end

    Rails.logger.info { "[PortfolioScoringAgent] gather_kpi_data → #{results.size} KPI report(s) with approved KPIs (periods: #{results.map { |r| r[:period] }.tally.inspect})" }
    results
  end

  # Snapshots all portfolio investments for this company into plain hashes for the prompt.
  def gather_investment_data(investor)
    investor.portfolio_investments.map do |pi|
      {
        instrument: pi.investment_instrument&.name,
        fund: pi.fund&.name,
        amount: pi.amount&.format,
        cost: pi.cost&.format,
        fmv: pi.fmv&.format,
        date: pi.try(:investment_date),
        status: pi.try(:status)
      }.compact
    end
  end

  # Valuations ordered newest-first so the LLM sees the current FMV before historical context.
  def gather_valuation_data(investor)
    investor.valuations.order(valuation_date: :desc).map do |v|
      {
        date: v.valuation_date,
        valuation: v.valuation&.format,
        per_share_value: v.per_share_value&.format,
        currency: v.currency
      }.compact
    end
  end

  # Extracts text from documents attached to recent Actual KPI reports.
  # `docs_from_last_n_reports` controls how many reports to pull from (default 1).
  # `document_name_filter` is an optional CSV of names to whitelist (blank = all).
  def gather_document_texts(investor)
    n = @support_agent.json_fields["docs_from_last_n_reports"].to_i
    n = 1 if n < 1

    name_csv = @support_agent.json_fields["document_name_filter"].to_s
    allowed_names = name_csv.split(",").map { |s| s.strip.downcase }.reject(&:empty?)

    Rails.logger.info { "[PortfolioScoringAgent] gather_document_texts: docs_from_last_n_reports=#{n}, document_name_filter=#{allowed_names.any? ? allowed_names.inspect : '(none — all docs)'}" }

    reports = investor.portfolio_kpi_reports
                      .where(tag_list: "Actual")
                      .order(as_of: :desc)
                      .limit(n)
    return [] if reports.empty?

    Rails.logger.info { "[PortfolioScoringAgent] Scanning documents from #{reports.size} KPI report(s): #{reports.map { |r| "#{r.period} #{r.as_of}" }.inspect}" }

    docs = []
    reports.each do |report|
      report.documents.each do |doc|
        next if doc.file.blank?

        # Apply name whitelist when configured
        if allowed_names.any? && allowed_names.exclude?(doc.name.to_s.downcase)
          Rails.logger.info { "[PortfolioScoringAgent] Skipping '#{doc.name}' — not in document_name_filter" }
          next
        end

        extension = File.extname(doc.file.original_filename.to_s).downcase
        next unless SUPPORTED_DOC_EXTENSIONS.include?(extension)

        text = read_document_text(doc)
        docs << { name: doc.name, date: report.as_of, text: text } if text.present?
      rescue StandardError => e
        Rails.logger.warn { "[PortfolioScoringAgent] Skipped document '#{doc.name}': #{e.message}" }
      end
    end
    docs
  end

  # Downloads a Document and extracts its text content.
  def read_document_text(doc)
    return nil if doc&.file.blank?

    extension = File.extname(doc.file.original_filename.to_s).downcase
    result    = nil

    Dir.mktmpdir("scoring_agent_") do |tmp_dir|
      filename  = File.basename(doc.file.original_filename.to_s).gsub(/[^0-9A-Za-z.\-_]/, '_')
      file_path = File.join(tmp_dir, filename)
      doc.file.open { |io| File.binwrite(file_path, io.read) }
      result = extract_text_from_file(file_path, extension)
    end
    result
  rescue StandardError => e
    Rails.logger.warn { "[PortfolioScoringAgent] Could not read document '#{doc.name}': #{e.message}" }
    nil
  end

  def extract_text_from_file(file_path, extension)
    case extension
    when '.txt', '.md'
      File.read(file_path, encoding: 'UTF-8')
    when '.pdf'
      require 'pdf-reader'
      PDF::Reader.new(file_path).pages.map(&:text).join("\n\n")
    when '.xlsx', '.xls'
      require 'roo'
      spreadsheet = Roo::Spreadsheet.open(file_path)
      spreadsheet.sheets.first(5).flat_map do |sheet_name|
        rows = []
        spreadsheet.sheet(sheet_name).each_row_streaming(pad_cells: true, max_rows: 200) do |row|
          vals = row.map { |c| c&.value.to_s.strip }.compact_blank
          rows << vals.join(" | ") if vals.any?
        end
        ["=== Sheet: #{sheet_name} ===", *rows]
      end.join("\n")
    when '.csv'
      File.read(file_path, encoding: 'UTF-8').lines.first(200).join
    when '.pptx', '.ppt'
      require 'zip'
      require 'nokogiri'
      parts = []
      Zip::File.open(file_path) do |zip|
        zip.glob('ppt/slides/slide*.xml')
           .sort_by { |e| e.name.match(/slide(\d+)\.xml/)[1].to_i }
           .each_with_index do |entry, i|
          doc = Nokogiri::XML(entry.get_input_stream.read).tap(&:remove_namespaces!)
          texts = doc.xpath('//t').map(&:text).compact_blank
          parts << "=== Slide #{i + 1} ===\n#{texts.join("\n")}" if texts.any?
        end
      end
      parts.join("\n\n")
    end
  rescue StandardError => e
    "Error extracting #{extension}: #{e.message}"
  end

  # --- Prompt & response helpers ---

  # Prepends the skill markdown (scoring criteria + benchmarks) as the system prompt context,
  # then injects all structured data as labelled JSON sections.
  # The min_points count is read from the agent's "Min Points Per Section" custom field (default 3).
  def build_scoring_prompt(skill_content, data)
    kpi_json         = JSON.pretty_generate(data[:kpi_reports])
    investment_json  = JSON.pretty_generate(data[:portfolio_investments])
    valuation_json   = JSON.pretty_generate(data[:valuations])
    custom_json      = JSON.pretty_generate(data[:custom_fields])
    doc_context      = format_documents(data[:documents])
    min_pts          = @support_agent.json_fields["min_points_per_section"].to_i
    min_pts          = 3 if min_pts < 1 # enforce sensible floor

    <<~PROMPT
      #{skill_content}

      ---

      Score the following portfolio company. Use all available data below.

      Company: #{data[:company_name]}
      Sector:  #{data[:sector]}

      ## KPI Reports
      #{kpi_json}

      ## Portfolio Investments
      #{investment_json}

      ## Valuations
      #{valuation_json}

      ## Company Details
      #{custom_json}

      ## Attached Documents
      #{doc_context.presence || 'No documents available.'}

      ---

      Return your assessment as a single JSON object. Required keys:
      - overall_score: integer 0–100
      - grade: string (e.g. "B+")
      - summary: string narrative overview
      - dimensions: array of {name, score, weight, rationale, positives, concerns}
        * positives: array of at least #{min_pts} specific data-backed positive signals (green)
        * concerns:  array of at least #{min_pts} specific data-backed concerns or risks (red)
      - strengths: array of at least #{min_pts} items
      - risks: array of at least #{min_pts} items
      - recommendations: array of at least #{min_pts} items
      - data_coverage {kpi_periods, valuations_used, documents_read}

      IMPORTANT: Every dimension object MUST include both "positives" and "concerns" arrays
      with at least #{min_pts} items each. Omitting them is not acceptable.

      Return ONLY the JSON object, wrapped in ```json ... ``` fences.
    PROMPT
  end

  # Formats extracted document texts as named, date-labelled sections for the LLM prompt.
  def format_documents(docs)
    return "" if docs.blank?

    docs.map { |d| "=== #{d[:name]} (#{d[:date]}) ===\n#{d[:text]}\n" }.join("\n---\n\n")
  end

  # Unwraps RubyLLM's response object to a plain string.
  # RubyLLM::Content wraps streamed/non-streamed responses differently.
  def extract_text_content(response)
    return response.to_s unless response.respond_to?(:content)

    content = response.content
    content.is_a?(RubyLLM::Content) ? content.text : content.to_s
  end

  def extract_score_json(raw)
    # Prefer fenced JSON block, fall back to bare object
    match = raw.match(/```json\s*(\{.+?\})\s*```/m) ||
            raw.match(/```\s*(\{.+?\})\s*```/m) ||
            raw.match(/(\{.+\})/m)
    raise "No JSON block found in LLM response" unless match

    parsed = JSON.parse(match[1])
    validate_score_keys!(parsed)
    parsed
  end

  def validate_score_keys!(parsed)
    missing = REQUIRED_SCORE_KEYS.reject { |k| parsed.key?(k) }
    raise "Score JSON missing required keys: #{missing.join(', ')}" if missing.any?
    raise "overall_score must be an integer 0–100" unless parsed["overall_score"].to_i.between?(0, 100)
    raise "dimensions must be a non-empty array" unless parsed["dimensions"].is_a?(Array) && parsed["dimensions"].any?
  end
end
