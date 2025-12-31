# PortfolioAssistant
#
# Orchestrator for the Portfolio Assistant AI.
# Handles queries about valuations, investments, KPIs, and documents.
#
class PortfolioAssistant
  AI_MODEL = ENV.fetch('DEFAULT_MODEL', nil).freeze

  def initialize(user:, chat: nil)
    @user = user
    @chat = chat
    @data_manager = PortfolioAssistantDataManager.new(user: user)
  end

  def tools
    [
      PortfolioAssistantTools::ListPortfolioCompanies.new(@data_manager),
      PortfolioAssistantTools::GetPortfolioCompanyDetails.new(@data_manager),
      PortfolioAssistantTools::ListValuations.new(@data_manager),
      PortfolioAssistantTools::ListPortfolioInvestments.new(@data_manager),
      PortfolioAssistantTools::GetCapTable.new(@data_manager),
      PortfolioAssistantTools::GetInvestmentsInCapTable.new(@data_manager),
      PortfolioAssistantTools::ListPortfolioKpis.new(@data_manager),
      PortfolioAssistantTools::ListFundRatios.new(@data_manager),
      PortfolioAssistantTools::ListDocuments.new(@data_manager),
      PortfolioAssistantTools::GetDocument.new(@data_manager),
      PortfolioAssistantTools::AnalyzeDocument.new(@data_manager),
      PortfolioAssistantTools::PlotChart.new(@data_manager)
    ]
  end

  def system_prompt
    <<~SYSTEM
      You are a helpful AI assistant specialized in Portfolio data for a Private Equity platform.
      You can retrieve information about portfolio companies, including their valuations, investments, KPIs, report extracts, and documents.

      Hyperlinking Rules:
      - Most data objects returned by tools include a `view_link` field.
      - ALWAYS use this `view_link` to hyperlink the primary identifier (like name or ID) in your markdown tables or text.
      - Use an HTML anchor tag with `target="_blank"` for these links to ensure they open in a new window.
      - Example: `<a href="/investors/123" target="_blank">Portfolio Company</a>` or `<a href="/documents/456" target="_blank">Document Name</a>`.

      You will format your responses as markdown, typically using tables for lists of data.
      Always use the provided tools to ensure accuracy. Never guess IDs or data.

      Guidelines:
      - If you need to find a portfolio company, use `ListPortfolioCompanies`.
      - Once you have the `portfolio_company_id`, you can query its valuations, investments, extracts, or documents.
      - For cap table information for a single company, use `GetCapTable`.
      - To get investment details across multiple portfolio companies (cross-company analysis), use `GetInvestmentsInCapTable`.
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
      assistant_type: 'PortfolioAssistant',
      model_id: AI_MODEL
    ).first_or_create!(
      owner: @user, # Default owner to user, can be overridden
      enable_broadcast: false,
      name: "Portfolio Assistant Chat #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}"
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

    Rails.logger.debug "\n🤖 Portfolio Assistant:"
    Rails.logger.debug response.content

    response
  end
end
