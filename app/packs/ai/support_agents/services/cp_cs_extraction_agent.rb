# frozen_string_literal: true

# Extracts conditions precedent (CP), conditions subsequent (CS), and other
# actionable obligations from portfolio investment agreements (SHA, SSA, SPA).
#
# Thin agent wrapper around the shared extraction engine in
# SideLetterObligationAgent — same prompts, same upsert/dedup logic, same
# SideLetterObligation model. Only the target resolution and config surface
# differ: this agent always operates on PortfolioInvestment records and has
# no side-letter-specific config fields.
#
# @see SideLetterObligationAgent for the extraction pipeline internals
class CpCsExtractionAgent < SideLetterObligationAgent
  DESCRIPTION = "Extracts CP/CS obligations from investment agreements for counsel review and alerts owners before due dates."

  LONG_DESCRIPTION = <<~DESC
    Tracks conditions precedent (CP), conditions subsequent (CS), and other
    actionable obligations from investment agreements — board approvals, regulatory
    filings, post-closing deliverables, reporting requirements — so none are missed.

    Steps:
    • Locate Document — finds the investment agreement on each portfolio investment by the configured tag.
    • Extract Obligations — reads the document and extracts structured obligations with source clause citations.
    • Save For Review — stores them as pending obligations; counsel approves, edits, or rejects each one.
      Only approved obligations generate tasks (recurring where applicable) and due-date alerts.

    The scheduled daily run is the enforcement pass: it alerts obligation owners on upcoming,
    due-today, and overdue items (one consolidated email per owner), escalating overdue items
    to the configured team tag.
  DESC

  SINGLE_LONG_DESCRIPTION = <<~DESC
    Extracts obligations from this investment's agreement document into the review queue.
    Approved obligations become tracked tasks with due-date alerts; nothing goes live
    without counsel review.
  DESC

  STEP_LABELS = {
    initialize_agent: "Initialize",
    locate_side_letter: "Locate Document",
    extract_obligations: "Extract Obligations",
    upsert_obligations: "Save For Review",
    generate_progress_reports: "Generate Report"
  }.freeze

  # @param entity_id [Integer, ActiveRecord::Base] entity ID for batch, or a single record for adhoc
  # @return [Array, ActiveRecord::Relation] portfolio investments with matching tagged documents
  def targets(entity_id)
    return [entity_id] if entity_id.is_a?(ActiveRecord::Base)

    agent_record = SupportAgent.where(entity_id: entity_id, agent_type: "CpCsExtractionAgent").last
    portfolio_investment_targets(entity_id, agent_record)
  end

  # @param support_agent [SupportAgent] agent config to validate
  # @return [Array<String>] list of config issues found
  def self.config_issues(support_agent)
    issues = []
    fields = support_agent.json_fields || {}

    tag = fields["investment_doc_tag"].to_s.strip
    if tag.blank?
      issues << "'investment_doc_tag' is not set — the agent cannot identify which documents to extract from. " \
                "Set it to the tag used on investment agreements (e.g. 'SHA')."
    end

    notify_tag = fields["notify_tag"].to_s.strip
    entity = support_agent.entity
    tag_matches = notify_tag.present? && entity.employees.where("tag_list LIKE ?", "%#{notify_tag}%").exists?
    fallback_exists = User.with_role(:company_admin).where(entity_id: entity.id).exists?
    if notify_tag.present? && !tag_matches
      issues << "'notify_tag' is '#{notify_tag}' but no employee carries that tag — ownerless alerts and overdue escalations would fall back to company admins."
    elsif notify_tag.blank? && !fallback_exists
      issues << "'notify_tag' is not set and the entity has no company admin to fall back to — ownerless alerts and overdue escalations have no recipients."
    end

    issues
  end

  # Mode dispatch: scheduled = daily enforcement; else = extraction.
  # @param support_agent_id [Integer] the agent's ID
  # @param targets [Array] target record IDs
  # @param user_id [Integer] user who triggered the run
  # @param entity_id [Integer] entity scope
  # @param with_steps [Boolean] whether to broadcast step progress
  # @param execution_mode [Symbol] :scheduled for enforcement, else extraction
  def self.process_batch(support_agent_id:, targets:, user_id:, entity_id:, with_steps: false, execution_mode: :adhoc_batch)
    if execution_mode == :scheduled
      support_agent = SupportAgent.find(support_agent_id)
      result = ObligationEnforcement.call(support_agent: support_agent)

      if result.success?
        counts = result[:counts]
        { successes: [{ id: support_agent.entity_id,
                        name: "Enforcement: #{counts['upcoming']} upcoming, #{counts['due']} due, #{counts['overdue']} overdue" }],
          errors: [] }
      else
        { successes: [], errors: [{ target_id: support_agent.entity_id, target_name: "Enforcement run", error: result[:error].to_s }] }
      end
    else
      run_batch(
        support_agent_id: support_agent_id,
        targets: targets,
        user_id: user_id,
        entity_id: entity_id,
        execution_mode: execution_mode
      )
    end
  end
end
