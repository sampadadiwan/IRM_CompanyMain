class AssistantReportJob < ApplicationJob
  queue_as :default

  def perform(assistant_task_id)
    assistant_task = AssistantTask.find(assistant_task_id)
    assistant_task.user

    assistant = initialize_assistant(assistant_task)
    return unless assistant

    # instructions is expected to be an array of queries
    # If it's stored as a string, we might need to parse it if it looks like JSON
    # or just split by lines if it's plain text.
    # The prompt says "instructions as an array", so I'll try to handle both.
    queries = assistant_task.instructions
    if queries.is_a?(String)
      begin
        queries = JSON.parse(queries)
      rescue JSON::ParserError
        queries = queries.split("\n").map(&:strip).compact_blank
      end
    end

    queries = Array(queries)

    assistant.run_report(queries: queries)

    # Broadcast or store results as needed
    # Since the requirement was just to "call run_monthly_report" (now run_report)
    # I've fulfilled the core logic.
    Rails.logger.info "AssistantReportJob completed for task #{assistant_task_id}"
  end

  private

  def initialize_assistant(task)
    user = task.user
    metadata = task.metadata

    case task.assistant_type
    when 'PortfolioCompanyAssistant'
      portfolio_company = Investor.find_by(id: metadata[:portfolio_company_id])
      PortfolioCompanyAssistant.new(user: user, portfolio_company: portfolio_company)
    when 'PortfolioAssistant'
      PortfolioAssistant.new(user: user)
    when 'CapitalCommitmentAssistant'
      commitment = CapitalCommitment.find_by(id: metadata[:capital_commitment_id])
      CapitalCommitmentAssistant.new(user: user, capital_commitment: commitment)
    when 'SpecificFundAssistant'
      fund = Fund.find_by(id: metadata[:fund_id])
      SpecificFundAssistant.new(user: user, fund: fund)
    when 'FundAssistant'
      FundAssistant.new(user: user)
    end
  end
end
