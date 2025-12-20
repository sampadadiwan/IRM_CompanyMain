require 'erb'

# FundAssistant
#
# The main orchestrator for the Private Equity Fund Assistant AI.
# This class configures the system prompt, initializes the data manager,
# and registers the available tools that the AI can use.
#
# It acts as the bridge between the AI consumer (e.g., AssistantQueryJob)
# and the underlying data and tools.
#
class FundAssistant
  AI_MODEL = 'gemini-3-flash-preview'.freeze

  # Initializes the FundAssistant.
  #
  # @param user [User] The user for whom the assistant is acting.
  #   Used for authorization (Pundit policies) and context.
  def initialize(user:, chat: nil)
    @user = user
    @chat = chat
    @data_manager = FundAssistantDataManager.new(user: user)
  end

  # --- Public API for Driver ---

  # Returns the list of instantiated tools available to the AI.
  # Each tool is initialized with the data manager to perform actual data retrieval.
  #
  # @return [Array<RubyLLM::Tool>] An array of tool instances.
  def tools
    [
      FundAssistantTools::ListFunds.new(@data_manager),
      FundAssistantTools::GetFundDetails.new(@data_manager),
      FundAssistantTools::ListCapitalCalls.new(@data_manager),
      FundAssistantTools::ListCapitalCommitments.new(@data_manager),
      FundAssistantTools::ListCapitalRemittances.new(@data_manager),
      FundAssistantTools::ListCapitalDistributions.new(@data_manager),
      FundAssistantTools::ListPortfolioInvestments.new(@data_manager),
      FundAssistantTools::ListFundRatios.new(@data_manager),
      FundAssistantTools::ListCapitalRemittancePayments.new(@data_manager),
      FundAssistantTools::ListCapitalDistributionPayments.new(@data_manager),
      FundAssistantTools::PlotChart.new(@data_manager)
    ]
  end

  # Generates the system prompt for the AI.
  # This prompt defines the AI's persona, capabilities, and rules for tool usage.
  #
  # @return [String] The system prompt.
  def system_prompt
    <<~SYSTEM
      You are a helpful AI assistant for a Private Equity Fund Management platform.
      You have access to tools to retrieve information and plot charts. You will format the response as markdown and typically as a table when possible. Always use the tools to get accurate data.

      Tool Usage Rules:
      - When searching for items like remittances or commitments, you can filter by `fund_id`, `folio_id`, or a Ransack `query`.
      - It is NOT necessary to provide a `fund_id` if a `folio_id` or a sufficiently specific `query` is given.
      - If the user mentions a status like "unpaid", "pending", or "overdue", translate this into a Ransack query (e.g., `{ status_not_eq: 'Paid' }`).
      - To create a visualization, first retrieve the data using a `list_` tool, then pass that data to the `PlotChart` tool.
      - Never guess IDs.

      Current User ID: #{@user.id}
      Todays Date: #{Time.zone.today}
    SYSTEM
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
      assistant_type: 'FundAssistant',
      model_id: AI_MODEL
    ).first_or_create!(
      owner: @user,
      enable_broadcast: false,
      name: "Fund Assistant Chat #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}"
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
