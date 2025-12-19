# PortfolioCompanyAssistant
#
# Orchestrator for the Portfolio Company Assistant AI.
# Handles queries about valuations, investments, KPIs, and documents.
#
class PortfolioCompanyAssistant
  AI_MODEL = 'gemini-3-flash-preview'.freeze

  def initialize(user:, chat: nil)
    @user = user
    @chat = chat
    @data_manager = PortfolioCompanyAssistantDataManager.new(user: user)
  end

  def tools
    [
      PortfolioCompanyAssistantTools::ListPortfolioCompanies.new(@data_manager),
      PortfolioCompanyAssistantTools::GetPortfolioCompanyDetails.new(@data_manager),
      PortfolioCompanyAssistantTools::ListValuations.new(@data_manager),
      PortfolioCompanyAssistantTools::ListPortfolioInvestments.new(@data_manager),
      PortfolioCompanyAssistantTools::ListPortfolioKpis.new(@data_manager),
      PortfolioCompanyAssistantTools::ListPortfolioReportExtracts.new(@data_manager),
      PortfolioCompanyAssistantTools::ListDocuments.new(@data_manager),
      PortfolioCompanyAssistantTools::PlotChart.new(@data_manager)
    ]
  end

  def system_prompt
    <<~SYSTEM
      You are a helpful AI assistant specialized in Portfolio Company data for a Private Equity platform.
      You can retrieve information about portfolio companies, including their valuations, investments, KPIs, report extracts, and documents.

      You will format your responses as markdown, typically using tables for lists of data.
      Always use the provided tools to ensure accuracy. Never guess IDs or data.

      Guidelines:
      - If you need to find a portfolio company, use `ListPortfolioCompanies`.
      - Once you have the `portfolio_company_id`, you can query its valuations, investments, extracts, or documents.
      - For KPIs, you can pass multiple `portfolio_company_ids` to `ListPortfolioKpis`.
      - For visualizations, fetch the data first, then use `PlotChart`.
      - Translate status or date filters into Ransack queries where appropriate.

      Current User ID: #{@user.id}
      Todays Date: #{Time.zone.today}
    SYSTEM
  end

  def run(prompt)
    Rails.logger.debug { "User: #{prompt}" }

    # If no chat is provided, we can either create one or use a transient chat if persistence isn't desired
    # But based on the task, we want to store request and responses, so we should have a chat.
    # If a chat was already provided in initialize, use it.
    # Otherwise, try to find an existing chat for today, or create a new one.
    @chat ||= Chat.where(
      user: @user,
      entity_id: @user.entity_id,
      assistant_type: 'PortfolioCompanyAssistant',
      model_id: AI_MODEL
    ).first_or_create!(
      owner: @user, # Default owner to user, can be overridden
      enable_broadcast: false,
      name: "Portfolio Company Assistant Chat #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}",
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
end
