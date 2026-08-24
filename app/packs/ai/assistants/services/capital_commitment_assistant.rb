require 'erb'

# CapitalCommitmentAssistant
#
# The main orchestrator for the Private Equity Capital Commitment Assistant AI.
# This class configures the system prompt, initializes the data manager,
# and registers the available tools that the AI can use.
#
class CapitalCommitmentAssistant < BaseAssistant
  DESCRIPTION = "I can help you with your capital commitment details, remittances, distributions, fund units, and documents.".freeze
  AI_MODEL = ENV.fetch('DEFAULT_MODEL', 'gemini-3-flash-preview').freeze

  MONTHLY_REPORT_QUERIES = [
    'Create a monthly LP report for this commitment as of today. Start with a 1-page summary: commitment size, called-to-date, remaining unfunded, distributed-to-date, and net cash flow to date.',
    'Show my commitment details (fund name, investor name, folio, commitment amount, commitment date if available) and highlight any key fields that affect funding/distributions.',
    'What is my remaining unfunded commitment right now, and has it changed since the start of this month?',
    # Due date lives on the associated capital call, not on the remittance itself -- query
    # via the nested Ransack attribute `capital_call_due_date` (see ListCapitalRemittances'
    # tool description). Grouping by "due date week" was dropped from the second query below:
    # perform_aggregation's group_by only supports grouping by an exact column value, not a
    # date-bucketed week, so that request was unanswerable by any tool regardless of this fix.
    'List all capital remittances created this month for this commitment. Include: notice date, due date (query capital_call_due_date), amount, currency, status, and any reference numbers.',
    'List all capital remittances due this month (regardless of when they were created) -- filter with capital_call_due_date_gteq/capital_call_due_date_lteq for this month\'s range. Sort by due date and include a total outstanding amount.',
    'List all unpaid or pending capital remittances for this commitment. Include days past due and total outstanding amount.',
    'List all overdue capital remittances for this commitment, sorted by most overdue first. Provide a total overdue amount at the bottom.',
    'Show the total capital called and total capital paid during this month for this commitment. Present as a table with subtotals.',
    'Show a month-by-month summary (last 12 months) of capital called vs capital paid for this commitment.',
    'Are there any capital remittances with missing due dates, missing amounts, or inconsistent statuses? List them as data quality issues.',
    'For each unpaid remittance, summarize what documents are available for it (capital call notice, invoice, bank details).',
    'List all capital distribution payments received/recorded this month for this commitment. Include: payment date, amount, currency, type/category if available, and reference numbers.',
    'Show the total distributions paid this month and year-to-date for this commitment. Present totals by currency (if multiple).',
    'Provide a month-by-month summary (last 12 months) of distributions for this commitment.',
    'Identify any distribution payments that look unusual (e.g., negative amounts, missing dates, duplicates). List them with details.',
    'List my current fund units for this commitment, including unit types, quantities, and latest prices.',
    'Create a net cash flow table for this month for this commitment: capital paid (outflow), distributions (inflow), and net (inflow - outflow).',
    'Create a cumulative cash flow roll-forward since inception for this commitment, by month: cumulative called, cumulative paid, cumulative distributions, and cumulative net cash flow.',
    'Plot a line chart of cumulative capital called vs time (monthly) for this commitment for the last 24 months.',
    'Plot a line chart of cumulative distributions vs time (monthly) for this commitment for the last 24 months.',
    'Plot a bar chart of monthly net cash flow (distributions minus capital paid) for this commitment for the last 12 months.',
    'Plot side-by-side bars (per month) of capital paid vs distributions for this commitment for the last 12 months.',
    'What capital remittances are coming due in the next 30/60/90 days for this commitment? Provide totals by month and list the individual items.',
    'Are there any expected distributions scheduled (based on recorded distribution payments or notices)? List what is known and the source document if applicable.'
  ].freeze

  # Initializes the CapitalCommitmentAssistant.
  #
  # @param user [User] The user for whom the assistant is acting.
  # @param capital_commitment [CapitalCommitment] The commitment context.
  def initialize(user:, capital_commitment:, chat: nil)
    super(user: user, chat: chat)
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
      CapitalCommitmentAssistantTools::ListFundUnits.new(@data_manager),
      CapitalCommitmentAssistantTools::ListDocuments.new(@data_manager),
      CapitalCommitmentAssistantTools::GetDocument.new(@data_manager),
      CapitalCommitmentAssistantTools::AnalyzeDocument.new(@data_manager),
      CapitalCommitmentAssistantTools::PlotChart.new(self),
      CapitalCommitmentAssistantTools::PlotChartFromQuery.new(self)
    ]
  end

  # Generates the system prompt for the AI.
  #
  # @return [String] The system prompt.
  def system_prompt
    prompt = <<~SYSTEM
      You are a helpful AI assistant for a Private Equity Fund Management platform, specialized in Capital Commitments.
      You have access to tools to retrieve information and plot charts related to commitments, remittances, distribution payments, and fund units.
      You will format the response as markdown and typically as a table when possible. Always use the tools to get accurate data.

      Hyperlinking Rules:
      - Most data objects returned by tools include a `view_link` field.
      - ALWAYS use this `view_link` to hyperlink the primary identifier (like name, folio, or ID) in your markdown tables or text.
      - DO NOT create a separate column for "view_link" or "Link". Instead, embed the link into the specific column it refers to.
      - Use an HTML anchor tag with `target="_blank"` for these links to ensure they open in a new window.
      - **CRITICAL**: Table headers MUST NEVER be hyperlinked.
      - Example: `<a href="/capital_commitments/123" target="_blank">Folio-123</a>` or `<a href="/documents/456" target="_blank">Document Name</a>`.

      Tool Usage Rules:
      - Efficiency Rule: For any request involving totals, sums, or breakdowns (e.g., "total amount", "breakdown by fund", "sum of collected"), you MUST use the `aggregate` parameter (`sum` or `group_by`). Fetching individual records to perform math is STRICTLY FORBIDDEN.
      - Mandatory Parameters for Aggregation:
        - When `aggregate` is `'sum'`, you MUST provide `aggregate_field` (the numeric field to sum).
        - When `aggregate` is `'group_by'`, you MUST provide both `aggregate_field` and `group_by_field`.
      - If the user mentions a status like "unpaid", "pending", or "overdue", translate this into a Ransack query for remittances.
      - **Optimized Charting**: To create a chart efficiently (without fetching large datasets into the chat history), you MUST use the `plot_chart_from_query` tool.
        - Provide the `resource` name (e.g., `'capital_remittances'`), any `query` filters, and a `prompt` for the chart.
        - Use this tool whenever the user asks for a chart based on a large collection of data.
      - Fallback Charting: If you already have the data in the conversation history, you can use `plot_chart(data: '...', prompt: '...')`. However, `plot_chart_from_query` is preferred for efficiency.
      - **IMPORTANT**: When the user asks for a chart, you MUST use either the `plot_chart_from_query` or `plot_chart` tool. In your FINAL response, you MUST summarize the chart's findings.
      - **CRITICAL**: To ensure the user sees the chart, you MUST include the literal string returned by the chart tools in your response. The chart tool returns an HTML snippet (e.g., `<div class="chart-wrap">...</div>`); you must output this snippet EXACTLY as received from the tool.
      - Never guess IDs. Always retrieve them using `list_` tools if needed.

      Current User ID: #{@user.id}
      Todays Date: #{Time.zone.today}
    SYSTEM

    prompt += <<~CONTEXT

      You are currently assisting with Capital Commitment ID: #{@capital_commitment.id} (Folio: #{@capital_commitment.folio_id}).
      The investor is #{@capital_commitment.investor_name} and the fund is #{@capital_commitment.fund&.name}.
      When listing remittances, distribution payments, or fund units, you should default to this commitment unless otherwise specified.
    CONTEXT

    prompt
  end

  def default_report_queries
    MONTHLY_REPORT_QUERIES
  end

  private

  def find_or_create_chat
    Chat.where(
      user: @user,
      entity_id: @user.entity_id,
      assistant_type: 'CapitalCommitmentAssistant',
      model: AI_MODEL,
      owner: @capital_commitment
    ).first_or_create!(
      enable_broadcast: false,
      name: "Capital Commitment Assistant Chat #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}"
    )
  end
end
