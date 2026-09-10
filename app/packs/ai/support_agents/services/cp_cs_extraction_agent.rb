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
# When run from a portfolio company page (target = Investor), the agent
# resolves the company's portfolio investments and processes each one
# sequentially through the extraction pipeline, broadcasting step progress
# against the Investor's report so the step UI advances on the investor page.
# Each step shows a counter (e.g. "Extracted 12 (2/5)") so the user sees
# progress across all investments.
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
    Extracts obligations from this company's investment agreement documents into the review queue.
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

  # Resolves extraction targets for this agent.
  # Accepts an entity ID (batch — all portfolio investments), a single
  # PortfolioInvestment (adhoc single run), or an Investor record
  # (portfolio company — scoped to that company's investments only).
  #
  # @param entity_id [Integer, PortfolioInvestment, Investor] entity ID, single record, or portfolio company
  # @return [Array, ActiveRecord::Relation] portfolio investments with matching tagged documents
  def targets(entity_id)
    return [entity_id] if entity_id.is_a?(PortfolioInvestment)

    # Portfolio company (Investor) → expand to its portfolio investments
    if entity_id.is_a?(Investor)
      agent_record = SupportAgent.where(entity_id: entity_id.entity_id, agent_type: "CpCsExtractionAgent").last
      investments = portfolio_investment_targets(entity_id.entity_id, agent_record)
      return investments.where(portfolio_company_id: entity_id.id)
    end

    agent_record = SupportAgent.where(entity_id: entity_id, agent_type: "CpCsExtractionAgent").last
    portfolio_investment_targets(entity_id, agent_record)
  end

  # Handles Investor (portfolio company) targets by expanding to portfolio
  # investments internally. The report stays owned by the Investor so the
  # step UI on the investor page receives broadcasts. For PortfolioInvestment
  # targets, delegates to the parent class.
  #
  # @param ctx [Hash] Trailblazer step context
  # @param target [Investor, PortfolioInvestment] the run target
  # @return [Boolean] always true
  def initialize_agent(ctx, target:, **)
    return super unless target.is_a?(Investor)

    report = ctx[:support_agent_report]
    mark_step_running(report, :initialize_agent) if report

    # Base class initialization (sets @support_agent and ctx[:llm])
    @support_agent = SupportAgent.find(ctx[:support_agent_id])
    ctx[:support_agent] = @support_agent
    ctx[:llm] = LlmService.ruby_llm_chat(entity: @support_agent.entity, model: @support_agent.effective_model)

    ctx[:model] = target
    ctx[:issues] = { extraction_issues: [] }

    # Resolve this company's portfolio investments with matching documents
    ctx[:investor_target] = target
    pi_targets = targets(target).to_a
    ctx[:investor_pi_targets] = pi_targets
    ctx[:source_mode] = :portfolio_investments

    if pi_targets.empty?
      if report
        mark_step_success(report, :initialize_agent,
                          message: "No portfolio investments found for #{target.investor_name}")
      end
      return true
    end

    if report
      mark_step_success(report, :initialize_agent,
                        message: "#{target.investor_name}: #{pi_targets.size} investment(s)")
    end
    true
  end

  # Locates documents across all portfolio investments for this company.
  # Each PI is checked for a matching tagged document. The step UI shows
  # a running counter (e.g. "Found: SHA (2/5)") as each PI is processed.
  # Falls back to the parent's single-PI logic when no investor targets.
  #
  # @param ctx [Hash] step context — populates ctx[:pi_docs] with per-PI results
  # @return [Boolean] always true
  def locate_side_letter(ctx, **)
    pi_targets = ctx[:investor_pi_targets]
    return super unless pi_targets

    report = ctx[:support_agent_report]
    total = pi_targets.size
    ctx[:pi_docs] = []

    pi_targets.each_with_index do |pi, idx|
      mark_step_running(report, :locate_side_letter) if report
      ctx[:portfolio_investment] = pi
      ctx[:extraction_doc] = nil
      locate_investment_document(ctx)

      pi_name = pi.try(:name) || "Investment #{pi.id}"
      doc_name = ctx[:extraction_doc]&.name || "no document"
      ctx[:pi_docs] << { pi: pi, doc: ctx[:extraction_doc] }

      if report
        mark_step_success(report, :locate_side_letter,
                          message: "#{doc_name} — #{pi_name} (#{idx + 1}/#{total})")
      end
    end
    true
  end

  # Extracts obligations from each located document via LLM. The step UI
  # shows a counter as each investment is extracted (e.g. "Extracted 12 (3/5)").
  # Accumulates all extracted rows in ctx[:all_extracted] for the upsert step.
  #
  # @param ctx [Hash] step context with ctx[:pi_docs] from locate step
  # @return [Boolean] always true
  def extract_obligations(ctx, **)
    pi_docs = ctx[:pi_docs]
    return super unless pi_docs

    report = ctx[:support_agent_report]
    total = pi_docs.size
    ctx[:all_extracted] = []

    pi_docs.each_with_index do |entry, idx|
      pi = entry[:pi]
      doc = entry[:doc]
      pi_name = pi.try(:name) || "Investment #{pi.id}"

      mark_step_running(report, :extract_obligations) if report

      if doc.nil?
        ctx[:all_extracted] << { pi: pi, extracted: [] }
        if report
          mark_step_success(report, :extract_obligations,
                            message: "Skipped — no document (#{idx + 1}/#{total})")
        end
        next
      end

      # Run LLM extraction for this document
      raw = ctx[:llm].ask(extraction_prompt(:portfolio_investments), with: [doc.file.url])
      rows = parse_response(raw)
      cited, _uncited = rows.partition { |r| r["source_clause"].to_s.strip.present? }
      ctx[:all_extracted] << { pi: pi, extracted: cited }

      if report
        mark_step_success(report, :extract_obligations,
                          message: "Extracted #{cited.size} — #{pi_name} (#{idx + 1}/#{total})")
      end
    end
    true
  rescue StandardError => e
    Rails.logger.error("[CpCsExtractionAgent] Extraction failed: #{e.message}")
    mark_step_failed(report, :extract_obligations, message: e.message) if report
    true
  end

  # Upserts extracted obligations for each portfolio investment. The step UI
  # shows a counter as each batch is saved (e.g. "Saved 12 (3/5)").
  # Also sets ctx[:extracted] with total count for the report step.
  #
  # @param ctx [Hash] step context with ctx[:all_extracted] from extract step
  # @return [Boolean] always true
  def upsert_obligations(ctx, **)
    all_extracted = ctx[:all_extracted]
    return super unless all_extracted

    report = ctx[:support_agent_report]
    total = all_extracted.size
    total_saved = 0

    all_extracted.each_with_index do |entry, idx|
      pi = entry[:pi]
      extracted = entry[:extracted]
      pi_name = pi.try(:name) || "Investment #{pi.id}"

      mark_step_running(report, :upsert_obligations) if report

      if extracted.blank?
        if report
          mark_step_success(report, :upsert_obligations,
                            message: "Nothing to save — #{pi_name} (#{idx + 1}/#{total})")
        end
        next
      end

      # Set up context for the parent's portfolio upsert method
      ctx[:portfolio_investment] = pi
      ctx[:extraction_doc] = ctx[:pi_docs]&.dig(idx, :doc)
      ctx[:extracted] = extracted
      ctx[:issues] = { extraction_issues: [] }
      upsert_portfolio_obligations(ctx)
      total_saved += extracted.size

      if report
        mark_step_success(report, :upsert_obligations,
                          message: "Saved #{extracted.size} — #{pi_name} (#{idx + 1}/#{total})")
      end
    end

    # Set ctx[:extracted] for generate_progress_reports redirect logic
    ctx[:extracted] = total_saved.positive? ? Array.new(total_saved) : []
    true
  end

  # Restores the Investor as the model for report generation and delegates
  # to the parent. The redirect targets the obligation matrix on the agent
  # show page.
  #
  # @param ctx [Hash] step context
  # @param model [Object] current target
  # @param support_agent [SupportAgent] agent record
  # @return [Object] result from super
  def generate_progress_reports(ctx, model:, support_agent:, **)
    ctx[:model] = ctx[:investor_target] || model
    super
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
