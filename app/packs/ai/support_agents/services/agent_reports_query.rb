# frozen_string_literal: true

# Query object that encapsulates report-loading logic for the different
# SupportAgent types displayed on the SupportAgent show page.
#
# Each agent type surfaces a different category of SupportAgentReport scoped
# by owner_type, ordered by a relevant timestamp column, and optionally
# filtered to a specific owner via +owner_id+.
#
# @example
#   query = AgentReportsQuery.new(@support_agent, params)
#   @fund_reports         = query.fund_reports
#   @portfolio_reports    = query.portfolio_reports
class AgentReportsQuery
  # @param support_agent [SupportAgent] the agent whose reports to load
  # @param params [Hash, ActionController::Parameters] request params (may contain +owner_id+)
  def initialize(support_agent, params = {})
    @support_agent = support_agent
    @params = params || {}
  end

  # Reports scoped to +Fund+ owners (CashFlowAssistantAgent only).
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def fund_reports
    return SupportAgentReport.none unless agent_type?("CashFlowAssistantAgent")

    agent_reports("Fund").order(updated_at: :desc)
  end

  # Reports scoped to +Investor+ owners (PortfolioCompanyAgent only).
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def portfolio_reports
    return SupportAgentReport.none unless agent_type?("PortfolioCompanyAgent")

    apply_owner_filter(agent_reports("Investor")).order(updated_at: :desc)
  end

  # Reports scoped to +Investor+ owners (PortfolioScoringAgent only).
  # Includes a JSONB filter to only surface reports carrying a top-level +score+ key.
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def scoring_reports
    return SupportAgentReport.none unless agent_type?("PortfolioScoringAgent")

    apply_owner_filter(agent_reports("Investor"))
      .where("json_fields LIKE '%\"score\":%'")
      .order(created_at: :desc)
  end

  # Reports scoped to +Investor+ owners (NoteSummarizerAgent only).
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def note_summaries
    return SupportAgentReport.none unless agent_type?("NoteSummarizerAgent")

    apply_owner_filter(agent_reports("Investor")).order(updated_at: :desc)
  end

  # Reports scoped to +Investor+ owners (PresentationAnalystAgent only).
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def presentation_reports
    return SupportAgentReport.none unless agent_type?("PresentationAnalystAgent")

    apply_owner_filter(agent_reports("Investor")).order(created_at: :desc)
  end

  # Reports scoped to +Deal+ owners (DealsReportAgent only).
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def deal_reports
    return SupportAgentReport.none unless agent_type?("DealsReportAgent")

    agent_reports("Deal").order(updated_at: :desc)
  end

  private

  # Checks whether the current support agent matches a given type.
  def agent_type?(type)
    @support_agent.agent_type == type
  end

  # Returns a base scope of reports for the given +owner_type+.
  def agent_reports(owner_type)
    SupportAgentReport
      .where(support_agent: @support_agent, owner_type: owner_type)
      .includes(:owner)
  end

  # Applies an +owner_id+ filter when the +owner_id+ param is present.
  def apply_owner_filter(scope)
    return scope if @params[:owner_id].blank?

    scope.where(owner_id: @params[:owner_id])
  end
end
