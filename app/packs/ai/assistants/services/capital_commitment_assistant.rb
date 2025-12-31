require 'erb'

# CapitalCommitmentAssistant
#
# The main orchestrator for the Private Equity Capital Commitment Assistant AI.
# This class configures the system prompt, initializes the data manager,
# and registers the available tools that the AI can use.
#
class CapitalCommitmentAssistant
  AI_MODEL = ENV.fetch('DEFAULT_MODEL', 'gemini-3-flash').freeze
  # A realistic set of prompts/queries an LP might ask to generate a monthly
  # reporting pack for a single capital commitment.
  #
  # These prompts are intentionally scoped to what this assistant can answer
  # using its available tools:
  # - `GetCommitmentDetails`
  # - `ListCapitalRemittances`
  # - `ListCapitalDistributionPayments`
  # - `ListDocuments` / `GetDocument` / `AnalyzeDocument`
  # - `PlotChart`
  MONTHLY_REPORT_QUERIES = [
    # Snapshot / headline
    'Create a monthly LP report for this commitment as of today. Start with a 1-page summary: commitment size, called-to-date, remaining unfunded, distributed-to-date, and net cash flow to date.',
    'Show my commitment details (fund name, investor name, folio, commitment amount, commitment date if available) and highlight any key fields that affect funding/distributions.',
    'What is my remaining unfunded commitment right now, and how has it changed since the start of this month?',

    # Capital calls / remittances (activity, status, exceptions)
    'List all capital remittances created this month for this commitment. Include: notice date, due date, amount, currency, status, and any reference numbers.',
    'List all capital remittances due this month (regardless of when they were created). Include amounts and status; group by due date week.',
    'List all unpaid or pending capital remittances for this commitment. Include days past due and total outstanding amount.',
    'List all overdue capital remittances for this commitment, sorted by most overdue first. Provide a total overdue amount at the bottom.',
    'Show the total capital called and total capital paid during this month for this commitment. Present as a table with subtotals.',
    'Show a month-by-month summary (last 12 months) of capital called vs capital paid for this commitment.',
    'Are there any capital remittances with missing due dates, missing amounts, or inconsistent statuses? List them as data quality issues.',
    'For each unpaid remittance, summarize what documents are available for it (capital call notice, invoice, bank details).',

    # Distributions (activity, type, status)
    'List all capital distribution payments received/recorded this month for this commitment. Include: payment date, amount, currency, type/category if available, and reference numbers.',
    'Show the total distributions paid this month and year-to-date for this commitment. Present totals by currency (if multiple).',
    'Provide a month-by-month summary (last 12 months) of distributions for this commitment.',
    'Identify any distribution payments that look unusual (e.g., negative amounts, missing dates, duplicates). List them with details.',

    # Net cash flow / roll-forward
    'Create a net cash flow table for this month for this commitment: capital paid (outflow), distributions (inflow), and net (inflow - outflow).',
    'Create a cumulative cash flow roll-forward since inception for this commitment, by month: cumulative called, cumulative paid, cumulative distributions, and cumulative net cash flow.',

    # Charts (must be supported by list_* then PlotChart)
    'Plot a line chart of cumulative capital called vs time (monthly) for this commitment for the last 24 months.',
    'Plot a line chart of cumulative distributions vs time (monthly) for this commitment for the last 24 months.',
    'Plot a bar chart of monthly net cash flow (distributions minus capital paid) for this commitment for the last 12 months.',
    'Plot side-by-side bars (per month) of capital paid vs distributions for this commitment for the last 12 months.',

    # Documents / notices (inventory + summarization)
    # 'List all documents linked to this commitment that were uploaded this month. Categorize them (capital call notice, distribution notice, statement, other) if possible.',
    # 'Find the most recent capital call notice document for this commitment and summarize: amount due, due date, purpose/notes, and payment instructions (if present).',
    # 'Find the most recent distribution notice document for this commitment and summarize: amount, payment date, breakdown if present, and any withholdings/taxes noted.',
    # 'Extract and summarize bank account / wire instructions from the latest capital call notice document. If multiple sets are present, list each distinctly.',
    # 'Check whether the latest call/distribution documents mention deadlines, penalties, or special instructions. Summarize the key compliance actions for an LP operations team.',
    # 'Compare the amounts/dates on the most recent capital call notice document to the remittance records. Flag any mismatch between the notice and the system data.',

    # Forward look / upcoming items
    'What capital remittances are coming due in the next 30/60/90 days for this commitment? Provide totals by month and list the individual items.',
    'Are there any expected distributions scheduled (based on recorded distribution payments or notices)? List what is known and the source document if applicable.'

    # Output formatting (monthly report pack)
    # 'Generate a monthly report pack for this commitment with sections: Summary, Capital Calls, Distributions, Net Cash Flow, Documents, and Exceptions. Use markdown tables and include the charts.',
    # 'Create a concise “LP Ops checklist” for this month for this commitment: what got paid, what is outstanding, what documents to file, and any follow-ups required.'
  ].freeze

  # Convenience helper to run a full "monthly report" pass by iterating through
  # MONTHLY_REPORT_QUERIES.
  #
  # This uses an ephemeral RubyLLM chat per question to avoid DB chat context overflow.
  # Adds simple pacing + retry/backoff to reduce burst-related rate-limit errors.
  #
  # @param queries [Array<String>] The prompts to ask in order.
  # @param sleep_seconds [Numeric] Delay between prompts to avoid bursty traffic.
  # @param max_retries [Integer] Retries per prompt when the provider returns rate-limit/quota errors.
  # @param base_backoff_seconds [Numeric] Base delay for exponential backoff (e.g., 1.0 -> 1s, 2s, 4s...).
  # @param on_error [Symbol] What to do when retries are exhausted. (:raise or :collect)
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

  private

  # Runs a single prompt using a fresh, in-memory RubyLLM chat with tools + instructions
  # so we don't keep sending an ever-growing DB conversation back to the provider (avoids context overflow).
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
        # If it's a repeated map key error, it's often because the LLM is confused about parameters.
        # We can try to ask again with a slightly different prompt or just return a helpful error.
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

  # Initializes the CapitalCommitmentAssistant.
  #
  # @param user [User] The user for whom the assistant is acting.
  # @param capital_commitment [CapitalCommitment] The commitment context.
  def initialize(user:, chat: nil, capital_commitment: nil)
    @user = user
    @chat = chat
    @capital_commitment = capital_commitment
    @data_manager = CapitalCommitmentAssistantDataManager.new(user: user, capital_commitment: capital_commitment)
  end

  # --- Public API for Driver ---

  # Returns the list of instantiated tools available to the AI.
  #
  # @return [Array<RubyLLM::Tool>] An array of tool instances.
  def tools
    [
      CapitalCommitmentAssistantTools::GetCommitmentDetails.new(@data_manager),
      CapitalCommitmentAssistantTools::ListCapitalRemittances.new(@data_manager),
      CapitalCommitmentAssistantTools::ListCapitalDistributionPayments.new(@data_manager),
      CapitalCommitmentAssistantTools::ListDocuments.new(@data_manager),
      CapitalCommitmentAssistantTools::GetDocument.new(@data_manager),
      CapitalCommitmentAssistantTools::AnalyzeDocument.new(@data_manager),
      CapitalCommitmentAssistantTools::PlotChart.new(@data_manager)
    ]
  end

  # Generates the system prompt for the AI.
  #
  # @return [String] The system prompt.
  def system_prompt
    prompt = <<~SYSTEM
      You are a helpful AI assistant for a Private Equity Fund Management platform, specialized in Capital Commitments.
      You have access to tools to retrieve information and plot charts related to commitments, remittances, and distribution payments.
      You will format the response as markdown and typically as a table when possible. Always use the tools to get accurate data.

      Hyperlinking Rules:
      - Most data objects returned by tools include a `view_link` field.
      - ALWAYS use this `view_link` to hyperlink the primary identifier (like name, folio, or ID) in your markdown tables or text.
      - Use an HTML anchor tag with `target="_blank"` for these links to ensure they open in a new window.
      - Example: `<a href="/capital_commitments/123" target="_blank">Folio-123</a>` or `<a href="/documents/456" target="_blank">Document Name</a>`.

      Tool Usage Rules:
      - If the user mentions a status like "unpaid", "pending", or "overdue", translate this into a Ransack query for remittances.
      - To create a visualization, first retrieve the data using a `list_` tool, then pass that data to the `PlotChart` tool.
      - When calling `PlotChart`, you MUST provide the `data` (as a JSON string) and the `prompt` (describing the chart). Example: `plot_chart(data: '[...]', prompt: 'Monthly cash flow')`.
      - Never guess IDs. Always retrieve them using `list_` tools if needed.

      Current User ID: #{@user.id}
      Todays Date: #{Time.zone.today}
    SYSTEM

    if @capital_commitment
      prompt += <<~CONTEXT

        You are currently assisting with Capital Commitment ID: #{@capital_commitment.id} (Folio: #{@capital_commitment.folio_id}).
        The investor is #{@capital_commitment.investor_name} and the fund is #{@capital_commitment.fund&.name}.
        When listing remittances or distribution payments, you should default to this commitment unless otherwise specified.
      CONTEXT
    end

    prompt
  end

  # Executes the AI assistant with a user prompt.
  #
  # @param prompt [String] The user's input.
  # @return [RubyLLM::Response] The assistant's response.
  def run(prompt)
    Rails.logger.debug { "User: #{prompt}" }

    # If no chat is provided, find or create one for today.
    @chat ||= Chat.where(
      user: @user,
      entity_id: @user.entity_id,
      assistant_type: 'CapitalCommitmentAssistant',
      model_id: AI_MODEL,
      owner: @capital_commitment || @user
    ).first_or_create!(
      enable_broadcast: false,
      name: "Capital Commitment Assistant Chat #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}"
    )

    @chat.with_instructions(system_prompt)
    @chat.with_tools(*tools)

    # RubyLLM handles the tool execution loop automatically
    response = @chat.ask(prompt)

    # The AI often includes an internal 'thought' process in the final text response.
    # We strip this internal monologue to only return the final, clean answer.
    content = response.content

    if content.is_a?(String) && content.include?("thought")
      response.content = content.split("thought").last.to_s.strip
    elsif content.respond_to?(:text) && content.text.to_s.include?("thought")
      content.text = content.text.to_s.split("thought").last.to_s.strip
    end

    Rails.logger.debug "\n🤖 Assistant:"
    Rails.logger.debug response.content

    response
  end
end
