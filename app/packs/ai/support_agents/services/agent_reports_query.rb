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
  # Surfaces both successful runs ("score" key) and failed runs ("error" key) —
  # filtering to "score" only would hide every failure from the UI. Step-tracking
  # reports are excluded via their "steps" key, which scoring reports never have.
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def scoring_reports
    return SupportAgentReport.none unless agent_type?("PortfolioScoringAgent")

    apply_owner_filter(agent_reports("Investor"))
      .where("(json_fields LIKE '%\"score\":%' OR json_fields LIKE '%\"error\":%') AND json_fields NOT LIKE '%\"steps\":%'")
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
    return SupportAgentReport.none unless agent_type?("DealsReportAgent") || agent_type?("DealManagementAgent")

    agent_reports("Deal").order(updated_at: :desc)
  end

  # Reports scoped to +Fund+ owners (RtaReconciliationAgent only).
  # Excludes the bare progress-tracking row (one per fund, reused/overwritten on
  # every run to drive the live step panel) — only rows carrying actual
  # reconciliation results (one new row per run) should show as history.
  # @return [ActiveRecord::Relation<SupportAgentReport>]
  def rta_reports
    return SupportAgentReport.none unless agent_type?("RtaReconciliationAgent")

    agent_reports("Fund").where("json_fields LIKE '%\"scheme_results\":%'").order(updated_at: :desc).limit(50)
  end

  # The Obligations tab for SideLetterObligationAgent shows the obligations
  # themselves (the LP Obligation Matrix), not SupportAgentReports — the matrix
  # IS the agent's living output. Optional owner_id narrows to one commitment.
  # @return [ActiveRecord::Relation<SideLetterObligation>]
  def side_letter_obligations
    return SideLetterObligation.none unless agent_type?("SideLetterObligationAgent")

    scope = SideLetterObligation.where(entity_id: @support_agent.entity_id)
                                .includes(:owner_user, side_letter: { capital_commitment: %i[investor fund] })
                                .order(Arel.sql("next_due_date IS NULL, next_due_date ASC"))
    scope = scope.joins(:side_letter).where(side_letters: { capital_commitment_id: @params[:owner_id] }) if @params[:owner_id].present?
    scope
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
