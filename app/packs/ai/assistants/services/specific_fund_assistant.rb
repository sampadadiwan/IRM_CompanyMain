# SpecificFundAssistant
#
# A specialized version of FundAssistant that is locked to a single fund.
# It ensures all queries and tools are focused exclusively on that fund.
#
class SpecificFundAssistant < FundAssistant
  DESCRIPTION = "I can help you with details, capital calls, commitments, and performance of a specific fund.".freeze
  AI_MODEL = ENV.fetch('DEFAULT_MODEL', 'gemini-3-flash').freeze

  # A set of queries to generate a monthly update/report for a fund.
  # Scoped to available tools:
  # - `GetSpecificFundDetails`
  # - `ListSpecificFundCapitalCalls`
  # - `ListSpecificFundCapitalCommitments`
  # - `ListSpecificFundCapitalRemittances`
  # - `ListSpecificFundCapitalDistributions`
  # - `ListSpecificFundPortfolioInvestments`
  # - `ListSpecificFundRatios`
  # - `PlotChart`
  MONTHLY_REPORT_QUERIES = [
    # 1. Summary & Profile
    "Provide a concise summary of this fund's profile and current status.",

    # 2. Performance Analysis (Trends & Outliers)
    "Analyze the trend of performance ratios (XIRR, TVPI, DPI) over the last few reporting periods. Identify any significant improvements or declines.",
    "Plot a line chart showing the historical trend of TVPI and DPI for this fund.",

    # 3. Capital Activity & Cash Flow Risk
    "Examine the capital call and distribution history. Are there any unusual spikes or outliers in the last 12 months? Analyze the 'Called vs Distributed' ratio trend.",
    "Plot a dual-axis chart showing cumulative capital called vs cumulative capital distributed over the fund's lifetime.",

    # 4. Portfolio Concentration & Risk
    "Analyze the portfolio for concentration risk. Identify the top 3 investments by FMV and calculate their percentage of the total portfolio. Are there any specific tags that are over-indexed?",
    "Plot a bar chart of the top 10 portfolio companies by FMV, highlighting any investment that represents more than 15% of the total FMV.",

    # 5. Investment Performance Outliers
    "Identify 'star' performers and 'underperformers' in the portfolio by comparing investment cost vs current FMV. List the top 3 and bottom 3 investments by gain/loss multiple.",

    # 6. LP Commitment & Remittance Health
    "Review the capital commitments. Identify any LPs with significant outstanding (unpaid) capital calls or delayed remittances. Is there a risk to the fund's liquidity?",

    # 7. Strategic Insights & Forward Look
    "Based on the current cash flow trends and portfolio valuation, provide a brief analysis of the fund's trajectory towards its target returns."
  ].freeze

  # Initializes the SpecificFundAssistant.
  #
  # @param user [User] The user for whom the assistant is acting.
  # @param fund [Fund] The specific fund to focus on (Mandatory).
  # @param chat [Chat, nil] Optional chat session.
  def initialize(user:, fund:, chat: nil)
    raise ArgumentError, "Fund is mandatory for SpecificFundAssistant" unless fund

    @user = user
    @fund = fund
    @chat = chat
    @data_manager = SpecificFundAssistantDataManager.new(user: user, fund: fund)
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

  # Returns the list of tools, specialized for the specific fund context.
  def tools
    [
      SpecificFundAssistantTools::GetSpecificFundDetails.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundCapitalCalls.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundCapitalCommitments.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundCapitalRemittances.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundCapitalDistributions.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundPortfolioInvestments.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundRatios.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundCapitalRemittancePayments.new(@data_manager),
      SpecificFundAssistantTools::ListSpecificFundCapitalDistributionPayments.new(@data_manager),
      SpecificFundAssistantTools::PlotChart.new(@data_manager)
    ]
  end

  # Custom system prompt for the specific fund context.
  def system_prompt
    <<~SYSTEM
      You are a helpful AI assistant for a Private Equity Fund Management platform, specifically assisting with the fund: **#{@fund.name}**.

      You ONLY answer questions and provide data related to **#{@fund.name}** (ID: #{@fund.id}). Do not provide information about other funds.

      You have access to tools to retrieve information and plot charts. Format responses as markdown and typically as a table when possible. Always use tools to get accurate data.

      Hyperlinking Rules:
      - Most data objects returned by tools include a `view_link` field.
      - ALWAYS use this `view_link` to hyperlink the primary identifier.
      - DO NOT create a separate column for "view_link" or "Link". Instead, embed the link into the specific column it refers to.
      - Use an HTML anchor tag with `target="_blank"`.

      Tool Usage Rules:
      - All data you retrieve MUST be for **#{@fund.name}** (ID: #{@fund.id}).
      - You MUST provide the `fund_id: "#{@fund.id}"` to ALL tools when calling them.
      - To create a visualization, first retrieve the data using a `list_` tool, then pass that data to the `PlotChart` tool.
      - When calling `PlotChart`, you MUST provide both the `data` (as a JSON string) and a `prompt` (describing the chart). Example: `plot_chart(data: '[...]', prompt: 'Monthly cash flow for #{@fund.name}')`.
      - Never guess IDs.

      Current User ID: #{@user.id}
      Todays Date: #{Time.zone.today}
      Current Fund: #{@fund.name} (ID: #{@fund.id})
    SYSTEM
  end

  # Executes the AI assistant.
  def run(prompt)
    Rails.logger.debug { "User (Specific Fund: #{@fund.name}): #{prompt}" }

    # If no chat is provided, find or create one for today, scoped to this fund.
    @chat ||= Chat.where(
      user: @user,
      entity_id: @user.entity_id,
      assistant_type: 'SpecificFundAssistant',
      model_id: AI_MODEL
      # Assuming we might want to store the fund context in metadata or similar if available
    ).first_or_create!(
      owner: @user,
      enable_broadcast: false,
      name: "#{@fund.name} Assistant Chat #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}"
    )

    @chat.with_instructions(system_prompt)
    @chat.with_tools(*tools)

    response = @chat.ask(prompt)

    # Clean up internal monologue
    content = response.content
    if content.is_a?(String) && content.include?("thought")
      response.content = content.split("thought").last.to_s.strip
    elsif content.respond_to?(:text) && content.text.to_s.include?("thought")
      content.text = content.text.to_s.split("thought").last.to_s.strip
    end

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
