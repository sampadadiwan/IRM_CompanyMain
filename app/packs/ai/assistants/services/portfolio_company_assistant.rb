# PortfolioCompanyAssistant
#
# Orchestrator for the Portfolio Company Assistant AI.
# Handles queries about a specific portfolio company's valuations, investments, KPIs, and documents.
#
class PortfolioCompanyAssistant
  DESCRIPTION = "I can help you with this portfolio company's valuations, investments, cap table, KPIs, fund ratios, and documents.".freeze
  AI_MODEL = ENV.fetch('DEFAULT_MODEL', 'gemini-3-flash').freeze

  # A set of queries to generate a monthly update/report for a portfolio company.
  # Scoped to available tools:
  # - `GetPortfolioCompanyDetails`
  # - `ListValuations`
  # - `ListPortfolioInvestments`
  # - `GetCapTable`
  # - `ListPortfolioKpis`
  # - `ListFundRatios`
  # - `ListDocuments` / `GetDocument` / `AnalyzeDocument`
  # - `PlotChart`
  MONTHLY_REPORT_QUERIES = [
    # 1. Summary & Profile
    "Provide a one-page summary of this company. Include its name, current stage, sector, and a brief profile. No Documents or KPIs required.",

    # 2. Performance Ratios
    # "What are the latest performance ratios for our investment in this company? Show TVPI, MOIC, and IRR if available.",
    # "Show a month-by-month summary (last 12 months) of the TVPI and MOIC for this company. Present as a table.",
    # "Plot a line chart of TVPI and MOIC vs time (monthly) for this company for the last 12 months.",

    # 3. Valuation History
    "List the valuation history for this company. Include date, per-share value, and currency. Highlight the most recent valuation.",
    "Plot a line chart of the company's valuation vs time using all available valuation data.",

    # 4. Investment Activity
    "List all our investment transactions in this company. Include dates, amounts, quantity, and whether it was a buy or sell.",
    "Plot a chart of investment amount and FMVs for this company",

    # 5. Cap Table & Ownership
    "Show the current cap table summary for this company. Group by investor name and show ownership percentages.",
    "Plot a pie chart of the current ownership structure (cap table) by investor name.",

    # 6. KPIs & Financials
    "List last 24 months, monthly KPIs for this company (e.g., Revenue, EBITDA, Cash Burn). Format as a table.",
    "Show the trend for 'Revenue' and 'EBITDA' over the last 12 months using available KPI reports. Present as a table with monthly columns.",
    "Plot a line chart of monthly Revenue and EBITDA for the last 12 months.",
    # "Plot a bar chart of monthly Cash Burn for the last 12 months.",

    # 7. Document Inventory
    "List the latest documents uploaded for this company in the last 30 days."

    # 8. Data Quality & Exceptions
    # "Are there any KPIs with missing values or unusual spikes in the last 3 reports? List them as potential data quality issues."
  ].freeze

  def initialize(user:, portfolio_company:, chat: nil)
    @user = user
    @portfolio_company = portfolio_company
    @chat = chat
    @data_manager = PortfolioCompanyAssistantDataManager.new(user: user, portfolio_company: portfolio_company)
  end

  # Convenience helper to run a full report pass.
  # @return [Array<Hash>] Array of { prompt:, response: } pairs.
  def run_monthly_report(
    queries: MONTHLY_REPORT_QUERIES,
    sleep_seconds: ENV.fetch('AI_MONTHLY_REPORT_SLEEP_SECONDS', '1').to_f,
    max_retries: ENV.fetch('AI_MONTHLY_REPORT_MAX_RETRIES', '5').to_i,
    base_backoff_seconds: ENV.fetch('AI_MONTHLY_REPORT_BACKOFF_SECONDS', '1.0').to_f,
    on_error: :collect
  )
    total_input_tokens = 0
    total_output_tokens = 0

    queries.map do |q|
      tries = 0

      begin
        result = ask_ephemeral(q)

        result = { content: result.to_s, input_tokens: 0, output_tokens: 0 } unless result.is_a?(Hash)

        response_text = result[:content]

        total_input_tokens += result[:input_tokens].to_i
        total_output_tokens += result[:output_tokens].to_i

        sleep(sleep_seconds) if sleep_seconds.positive?

        Rails.logger.debug "\n\n#############################################"
        Rails.logger.debug { "Cumulative Tokens - Input: #{total_input_tokens}, Output: #{total_output_tokens}, Total: #{total_input_tokens + total_output_tokens}" }
        Rails.logger.debug "#############################################\n\n"

        { prompt: q, response: response_text, input_tokens: result[:input_tokens], output_tokens: result[:output_tokens] }
      rescue RubyLLM::RateLimitError => e
        tries += 1
        raise e if tries > max_retries && on_error == :raise

        if tries > max_retries
          { prompt: q, error: e.class.name, message: e.message }
        else
          backoff = base_backoff_seconds * (2**(tries - 1))
          jitter = rand * 0.25
          sleep(backoff + jitter)
          retry
        end
      end
    end
  end

  def tools
    [
      PortfolioCompanyAssistantTools::GetPortfolioCompanyDetails.new(@data_manager),
      PortfolioCompanyAssistantTools::ListValuations.new(@data_manager),
      PortfolioCompanyAssistantTools::ListPortfolioInvestments.new(@data_manager),
      PortfolioCompanyAssistantTools::GetCapTable.new(@data_manager),
      PortfolioCompanyAssistantTools::GetInvestmentsInCapTable.new(@data_manager),
      PortfolioCompanyAssistantTools::ListPortfolioKpis.new(@data_manager),
      PortfolioCompanyAssistantTools::ListFundRatios.new(@data_manager),
      PortfolioCompanyAssistantTools::ListDocuments.new(@data_manager),
      PortfolioCompanyAssistantTools::GetDocument.new(@data_manager),
      PortfolioCompanyAssistantTools::AnalyzeDocument.new(@data_manager),
      PortfolioCompanyAssistantTools::PlotChart.new(@data_manager)
    ]
  end

  def system_prompt
    <<~SYSTEM
      You are a helpful AI assistant specialized in data for a single Portfolio Company: #{@portfolio_company.investor_name}.
      You can retrieve information about this company, including its valuations, investments, KPIs, and documents.

      Hyperlinking Rules:
      - Most data objects returned by tools include a `view_link` field.
      - ALWAYS use this `view_link` to hyperlink the primary identifier (like name or ID) in your markdown tables or text.
      - DO NOT create a separate column for "view_link" or "Link". Instead, embed the link into the specific column it refers to.
      - Use an HTML anchor tag with `target="_blank"` for these links to ensure they open in a new window.
      - Example: `<a href="/portfolio_investments/123" target="_blank">Investment ID</a>` or `<a href="/documents/456" target="_blank">Document Name</a>`.

      You will format your responses as markdown, typically using tables for lists of data.
      Always use the provided tools to ensure accuracy.

      Guidelines:
      - You are already scoped to the portfolio company: #{@portfolio_company.investor_name} (ID: #{@portfolio_company.id}).
      - Use `GetPortfolioCompanyDetails` to get basic info about this company.
      - Use `ListValuations` to see how the company's value has changed.
      - Use `ListPortfolioInvestments` to see investment transactions.
      - Use `GetCapTable` for the current ownership structure.
      - Use `ListPortfolioKpis` for financial and operational metrics.
      - For visualizations, fetch the data first, then use `PlotChart`.

      Current User ID: #{@user.id}
      Todays Date: #{Time.zone.today}
    SYSTEM
  end

  def run(prompt)
    Rails.logger.debug { "User: #{prompt}" }

    @chat ||= Chat.where(
      user: @user,
      entity_id: @user.entity_id,
      assistant_type: 'PortfolioCompanyAssistant',
      model_id: AI_MODEL,
      owner: @portfolio_company
    ).first_or_create!(
      enable_broadcast: false,
      name: "Portfolio Company Assistant Chat (#{@portfolio_company.investor_name}) #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}"
    )

    @chat.with_instructions(system_prompt)
    @chat.with_tools(*tools)

    response = @chat.ask(prompt)

    content = response.content

    if content.is_a?(String) && content.include?("thought")
      response.content = content.split("thought").last.to_s.strip
    elsif content.respond_to?(:text) && content.text.to_s.include?("thought")
      content.text = content.text.to_s.split("thought").last.to_s.strip
    end

    Rails.logger.debug "\n🤖 Portfolio Company Assistant:"
    Rails.logger.debug response.content

    response
  end

  private

  # Runs a single prompt using a fresh, in-memory RubyLLM chat.
  def ask_ephemeral(prompt)
    Rails.logger.debug "\n\n#############################################"
    Rails.logger.debug { "🤖 Asking ephemeral prompt: #{prompt.inspect}" }

    begin
      response = run(prompt)
    rescue StandardError => e
      Rails.logger.debug { "⚠️ Caught BadRequestError: #{e.message}" }
      Rails.logger.debug e.backtrace.join("\n")
      if e.message.include?("Repeated map key")
        Rails.logger.debug "⚠️ Caught repeated map key error, retrying without some tools or instructions..."
        return "Error: The AI encountered a technical issue with the data query (repeated parameters). Please try rephrasing your question."
      end
      raise e
    end

    content = response.content

    if content.is_a?(String) && content.include?("thought")
      content = content.split("thought").last.to_s.strip
    elsif content.respond_to?(:text) && content.text.to_s.include?("thought")
      content.text = content.text.to_s.split("thought").last.to_s.strip
      content = content.text
    end

    Rails.logger.debug { "🤖 Ephemeral response: #{content.inspect}" }
    { content: content, input_tokens: response.input_tokens, output_tokens: response.output_tokens }
  end
end
