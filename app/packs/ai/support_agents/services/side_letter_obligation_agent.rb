# frozen_string_literal: true

# Extracts obligations ("covenants") from legal documents and enforces their
# due dates. Supports two source types (configured per agent instance):
#
#   - Capital commitments: reads side letter PDFs, extracts LP obligations
#   - Portfolio investments: reads SHA/SSA documents, extracts CP/CS obligations
#
# Two run modes (mirrors PortfolioCompanyAgent's mode dispatch):
#   - Extraction (manual single/batch): locate the target document on each
#     record by the configured label/tag, LLM-extract structured obligations,
#     and save them as SideLetterObligation rows in pending_review.
#     NOTHING becomes active without counsel approval (ObligationApprove) —
#     extraction never creates tasks or alerts.
#   - Enforcement (scheduled daily): delegates to ObligationEnforcement, which
#     alerts owners on upcoming / due-today / overdue obligation tasks.
#
# Config in SupportAgent.json_fields (via form custom fields):
#   source_type                 — "capital_commitments" or "portfolio_investments"
#   side_letter_doc_label       — document name identifying a side letter (default "Side Letter")
#   investment_doc_tag          — document tag identifying investment agreements (e.g. "SHA")
#   auto_extract_on_upload      — Yes/No: extract when a matching document lands
#   default_reminder_days_before — lead-time default stamped on new obligations
#   overdue_escalation_days     — overdue re-alert cadence for enforcement
#   notify_tag                  — employee tag for ownerless alerts + escalations
class SideLetterObligationAgent < SupportAgentService
  DESCRIPTION = "Extracts side letter obligations for counsel review and alerts owners before due dates."

  LONG_DESCRIPTION = <<~DESC
    Tracks the obligations (covenants) your side letters create — reporting deadlines,
    fee arrangements, co-investment rights, notice requirements — so none are missed.

    Steps:
    • Locate Side Letter — finds the side letter document on each commitment by the configured label.
    • Extract Obligations — reads the document and extracts structured obligations with source clause citations.
    • Save For Review — stores them as pending obligations; counsel approves, edits, or rejects each one.
      Only approved obligations generate tasks (recurring where applicable) and due-date alerts.

    The scheduled daily run is the enforcement pass: it alerts obligation owners on upcoming,
    due-today, and overdue items (one consolidated email per owner), escalating overdue items
    to the configured team tag.
  DESC

  SINGLE_LONG_DESCRIPTION = <<~DESC
    Extracts obligations from this commitment's side letter document into the review queue.
    Approved obligations become tracked tasks with due-date alerts; nothing goes live
    without counsel review.
  DESC

  STEP_LABELS = {
    initialize_agent: "Initialize",
    locate_side_letter: "Locate Side Letter",
    extract_obligations: "Extract Obligations",
    upsert_obligations: "Save For Review",
    generate_progress_reports: "Generate Report"
  }.freeze

  DEFAULT_DOC_LABEL = "Side Letter"

  step :initialize_agent
  step :locate_side_letter
  step :extract_obligations
  step :upsert_obligations
  step :generate_progress_reports

  # Extraction targets: records that have the configured document attached.
  # Returns capital commitments (default) or portfolio investments based on
  # the agent's source_type config. Accepts a single record (adhoc single
  # run) or an entity_id (batch/scheduled resolution).
  # @param entity_id [Integer, ActiveRecord::Base] entity ID for batch, or a single record for adhoc
  # @return [ActiveRecord::Relation] scoped records to extract from
  def targets(entity_id)
    return [entity_id] if entity_id.is_a?(ActiveRecord::Base)

    agent_record = SupportAgent.where(entity_id: entity_id, agent_type: "SideLetterObligationAgent").last
    source_type = (agent_record&.json_fields || {})["source_type"].to_s

    if source_type == "portfolio_investments"
      portfolio_investment_targets(entity_id, agent_record)
    else
      capital_commitment_targets(entity_id, agent_record)
    end
  end

  private

  # @param entity_id [Integer] entity to scope commitments for
  # @param agent_record [SupportAgent] agent config record
  # @return [ActiveRecord::Relation<CapitalCommitment>] commitments with side letter documents
  def capital_commitment_targets(entity_id, agent_record)
    label = self.class.doc_label(agent_record)
    scope = CapitalCommitment.where(entity_id: entity_id)
    commitment_docs = Document.where(entity_id: entity_id, owner_type: "CapitalCommitment", template: [nil, false])
    by_doc = self.class.side_letter_documents(commitment_docs, label).select(:owner_id)
    by_record = SideLetter.where(entity_id: entity_id).select(:capital_commitment_id)
    scope.where(id: by_doc).or(scope.where(id: by_record))
  end

  # @param entity_id [Integer] entity to scope portfolio investments for
  # @param agent_record [SupportAgent] agent config record
  # @return [ActiveRecord::Relation<PortfolioInvestment>] investments with matching tagged documents
  def portfolio_investment_targets(entity_id, agent_record)
    tags = split_investment_doc_tags(agent_record)
    scope = PortfolioInvestment.where(entity_id: entity_id)
    return scope.none if tags.empty?

    tagged_docs = Document.where(entity_id: entity_id, owner_type: "PortfolioInvestment", template: [nil, false])
    tagged_docs = tagged_docs.where(*investment_tag_conditions(tags))
    scope.where(id: tagged_docs.select(:owner_id))
  end

  def self.doc_label(support_agent)
    (support_agent&.json_fields || {})["side_letter_doc_label"].presence || DEFAULT_DOC_LABEL
  end

  # A document is a side letter if it carries the configured name label, or if
  # it is tagged "Side Letter"/"SideLetter" in any casing. Tags let GPs keep
  # their own file-naming conventions and still feed the agent.
  TAG_PATTERNS = ["%side letter%", "%sideletter%"].freeze

  # SQL form, for picking side letter documents out of a Document scope.
  # LOWER + LIKE rather than a collation-dependent bare LIKE, so this behaves
  # identically on MySQL (dev/prod) and SQLite (test).
  def self.side_letter_documents(scope, label)
    tag_sql = "LOWER(COALESCE(documents.tag_list, '')) LIKE :a OR LOWER(COALESCE(documents.tag_list, '')) LIKE :b"
    scope.where(name: label)
         .or(scope.where(tag_sql, a: TAG_PATTERNS[0], b: TAG_PATTERNS[1]))
  end

  # Ruby form, for deciding about one already-loaded document (upload hook).
  def self.side_letter_document?(document, label)
    return true if document.name == label

    tags = document.tag_list.to_s.downcase
    tags.include?("side letter") || tags.include?("sideletter")
  end

  def self.config_issues(support_agent)
    issues = []
    fields = support_agent.json_fields || {}
    issues << "'side_letter_doc_label' is not set — falling back to '#{DEFAULT_DOC_LABEL}'. Set it to the document name your side letters are uploaded under." if fields["side_letter_doc_label"].to_s.strip.blank?
    # notify_tag is tenant-specific so setup seeds it blank on purpose. Blank is
    # fine at runtime — enforcement falls back to company admins — so only warn
    # when the tag matches nobody AND there is no fallback either.
    tag = fields["notify_tag"].to_s.strip
    entity = support_agent.entity
    tag_matches = tag.present? && entity.employees.where("tag_list LIKE ?", "%#{tag}%").exists?
    fallback_exists = User.with_role(:company_admin).where(entity_id: entity.id).exists?
    if tag.present? && !tag_matches
      issues << "'notify_tag' is '#{tag}' but no employee carries that tag — ownerless alerts and overdue escalations would fall back to company admins."
    elsif tag.blank? && !fallback_exists
      issues << "'notify_tag' is not set and the entity has no company admin to fall back to — ownerless alerts and overdue escalations have no recipients."
    end
    issues
  end

  # Mode dispatch: scheduled = daily enforcement (entity-wide due-date scan);
  # everything else = extraction over the given commitments via the shared
  # batch runner.
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

  # Initializes the extraction context for the given target record.
  # Sets :source_mode so downstream steps know whether to follow the
  # commitment (side letter) or portfolio investment (SHA/SSA) path.
  # Broadcasts step progress when a report is attached (step-UI run).
  #
  # @param ctx [Hash] step context — populated with :commitment or :portfolio_investment
  #   depending on the target record type, plus :source_mode for downstream branching
  # @param target [CapitalCommitment, PortfolioInvestment] the record to extract from
  # @return [Boolean] always true so Trailblazer continues
  def initialize_agent(ctx, target:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :initialize_agent) if report
    super
    ctx[:model] = target
    ctx[:issues] = { extraction_issues: [] }
    if target.is_a?(PortfolioInvestment)
      ctx[:portfolio_investment] = target
      ctx[:source_mode] = :portfolio_investments
    else
      ctx[:commitment] = target
      ctx[:source_mode] = :capital_commitments
    end
    target_name = target.try(:name) || target.try(:investor_name) || "ID=#{target.id}"
    mark_step_success(report, :initialize_agent, message: "Initialized for #{target_name}") if report
    true
  end

  # Locates the document to extract from on the current target record.
  # For commitments: matches by configured name label or side letter tag.
  # For portfolio investments: matches by configured document tag.
  # Broadcasts step progress when a report is attached (step-UI run).
  #
  # @param ctx [Hash] step context — sets :extraction_doc with the found document
  # @return [Boolean] always true so Trailblazer continues
  def locate_side_letter(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :locate_side_letter) if report
    if ctx[:source_mode] == :portfolio_investments
      locate_investment_document(ctx)
    else
      locate_commitment_document(ctx)
    end
    if ctx[:extraction_doc]
      mark_step_success(report, :locate_side_letter, message: "Found: #{ctx[:extraction_doc].name}") if report
    else
      mark_step_skipped(report, :locate_side_letter, message: "No matching document found") if report
    end
    true
  end

  # @param ctx [Hash] step context with :commitment set
  def locate_commitment_document(ctx)
    commitment = ctx[:commitment]
    label = self.class.doc_label(@support_agent)
    # Newest document carrying the configured label or a side letter tag.
    ctx[:extraction_doc] = self.class
                               .side_letter_documents(commitment.documents.where(template: [nil, false]), label)
                               .order(:id).last
    # Fallback for side letters recorded by hand: the user already told us which
    # document is the side letter, so honour that whatever it is named.
    ctx[:extraction_doc] ||= SideLetter.where(capital_commitment_id: commitment.id)
                                       .order(:id).last&.document

    if ctx[:extraction_doc].nil?
      ctx[:issues][:extraction_issues] << {
        type: :no_document,
        message: "No document named '#{label}' on this commitment and no side letter recorded — nothing to extract",
        severity: :info
      }
    end
  end

  # Locates all documents on the portfolio investment whose tag_list matches
  # any of the comma-separated tags in +investment_doc_tag+ config. Stores all
  # matches in +ctx[:extraction_docs]+ and the newest in +ctx[:extraction_doc]+
  # for backward compatibility with the parent's single-doc extraction path.
  #
  # @param ctx [Hash] step context with :portfolio_investment set
  # @return [void]
  def locate_investment_document(ctx)
    investment = ctx[:portfolio_investment]
    tags = split_investment_doc_tags(@support_agent)
    if tags.empty?
      ctx[:issues][:extraction_issues] << {
        type: :no_document,
        message: "No investment document tag configured — nothing to extract",
        severity: :info
      }
      return
    end

    # All documents on this investment matching any configured tag (e.g. "SHA,SSA")
    matching_docs = investment.documents
                              .where(template: [nil, false])
                              .where(*investment_tag_conditions(tags))
                              .order(:id)

    ctx[:extraction_docs] = matching_docs.to_a
    # Backward compat — parent's single-PI extract_obligations reads ctx[:extraction_doc]
    ctx[:extraction_doc] = ctx[:extraction_docs].last

    if ctx[:extraction_docs].blank?
      ctx[:issues][:extraction_issues] << {
        type: :no_document,
        message: "No document tagged '#{tags.join(", ")}' on this investment — nothing to extract",
        severity: :info
      }
    end
  end

  # Sends the located document to the LLM for structured obligation extraction.
  # Discards any items the LLM cannot cite to a specific clause (hallucination guard).
  # Broadcasts step progress when a report is attached (step-UI run).
  #
  # @param ctx [Hash] step context with :extraction_doc, :source_mode, :llm
  # @return [Boolean] always true so Trailblazer continues
  def extract_obligations(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :extract_obligations) if report
    ctx[:extracted] = []
    doc = ctx[:extraction_doc]
    if doc.nil?
      mark_step_skipped(report, :extract_obligations, message: "No document to extract from") if report
      return true
    end

    raw = ctx[:llm].ask(extraction_prompt(ctx[:source_mode]), with: [doc.file.url])
    rows = parse_response(raw)

    cited, uncited = rows.partition { |r| r["source_clause"].to_s.strip.present? }
    if uncited.any?
      ctx[:issues][:extraction_issues] << {
        type: :discarded,
        message: "#{uncited.size} extracted item(s) had no source clause citation and were discarded",
        severity: :warning
      }
    end

    ctx[:extracted] = cited
    mark_step_success(report, :extract_obligations, message: "Extracted #{cited.size} obligation(s)") if report
    true
  rescue StandardError => e
    Rails.logger.error("[SideLetterObligationAgent] Extraction failed for Document ID=#{doc&.id}: #{e.message}")
    ctx[:issues][:extraction_issues] << {
      type: :extraction_failed,
      message: "Extraction failed: #{e.message}",
      severity: :blocking
    }
    mark_step_failed(report, :extract_obligations, message: e.message) if report
    true
  end

  # Persists extracted obligations. For commitments: creates/finds a SideLetter
  # anchor and links obligations via side_letter_id. For portfolio investments:
  # links obligations directly via the sourceable polymorphic.
  # Broadcasts step progress when a report is attached (step-UI run).
  #
  # @param ctx [Hash] step context with :extraction_doc, :extracted, :source_mode
  # @return [Boolean] always true so Trailblazer continues
  def upsert_obligations(ctx, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :upsert_obligations) if report
    doc = ctx[:extraction_doc]
    if doc.nil? || ctx[:extracted].blank?
      mark_step_skipped(report, :upsert_obligations, message: "Nothing to save") if report
      return true
    end

    if ctx[:source_mode] == :portfolio_investments
      upsert_portfolio_obligations(ctx)
    else
      upsert_commitment_obligations(ctx)
    end
    mark_step_success(report, :upsert_obligations, message: "Saved #{ctx[:extracted].size} obligation(s)") if report
    true
  end

  # @param ctx [Hash] step context with :commitment, :extraction_doc, :extracted
  def upsert_commitment_obligations(ctx)
    commitment = ctx[:commitment]
    doc = ctx[:extraction_doc]
    side_letter = SideLetter.find_or_create_by!(capital_commitment: commitment, document: doc) do |sl|
      sl.entity_id = commitment.entity_id
    end
    re_extraction = side_letter.side_letter_obligations.exists?

    created = 0
    ctx[:extracted].each do |row|
      created += 1 if upsert_row(side_letter, row, re_extraction)
    end

    if created.positive?
      side_letter.update!(extraction_status: "ai_extracted")
      report_pending(ctx, created)
    else
      report_unchanged(ctx)
    end
  end

  # @param ctx [Hash] step context with :portfolio_investment, :extraction_doc, :extracted
  def upsert_portfolio_obligations(ctx)
    investment = ctx[:portfolio_investment]
    re_extraction = SideLetterObligation.where(sourceable: investment).exists?

    created = 0
    ctx[:extracted].each do |row|
      created += 1 if upsert_portfolio_row(investment, row, re_extraction)
    end

    report_pending(ctx, created) if created.positive?
    report_unchanged(ctx) if created.zero?
  end

  # Returns true when a new pending row was created (or an existing pending row
  # refreshed). Approved rows are never touched: a changed extraction lands as
  # a NEW pending delta beside them. Same-key rejected rows stay rejected.
  def upsert_row(side_letter, row, re_extraction)
    attrs = row_attributes(side_letter, row)
    existing = side_letter.side_letter_obligations
                          .where(source_clause: attrs[:source_clause], obligation_type: attrs[:obligation_type])
                          .order(:id).last

    case existing&.review_status
    when nil
      side_letter.side_letter_obligations.create!(attrs.merge(delta: re_extraction))
      true
    when "pending_review"
      # Keep the review queue fresh — re-extraction refines the pending draft
      existing.update!(attrs)
      false
    when "approved"
      return false unless content_changed?(existing, attrs)

      side_letter.side_letter_obligations.create!(attrs.merge(delta: true))
      true
    else # rejected — counsel already said no; do not resurface the same clause
      false
    end
  end

  # Portfolio investment variant of upsert_row — uses sourceable polymorphic
  # instead of side_letter_id. Same dedup logic: pending updated, approved
  # creates delta, rejected skipped.
  # @param investment [PortfolioInvestment] the source record
  # @param row [Hash] LLM-extracted obligation data
  # @param re_extraction [Boolean] true if obligations already exist for this investment
  # @return [Boolean] true if a new pending row was created
  def upsert_portfolio_row(investment, row, re_extraction)
    attrs = portfolio_row_attributes(investment, row)
    existing = SideLetterObligation
               .where(sourceable: investment, source_clause: attrs[:source_clause], obligation_type: attrs[:obligation_type])
               .order(:id).last

    case existing&.review_status
    when nil
      SideLetterObligation.create!(attrs.merge(delta: re_extraction))
      true
    when "pending_review"
      existing.update!(attrs)
      false
    when "approved"
      return false unless content_changed?(existing, attrs)

      SideLetterObligation.create!(attrs.merge(delta: true))
      true
    else
      false
    end
  end

  def content_changed?(existing, attrs)
    %i[title trigger_type frequency_rrule next_due_date].any? do |key|
      existing[key].to_s != attrs[key].to_s
    end
  end

  def row_attributes(side_letter, row)
    {
      entity_id: side_letter.entity_id,
      obligation_type: normalize_enum(row["obligation_type"], SideLetterObligation.obligation_types.keys, "other"),
      title: row["title"].to_s.strip.presence || "Untitled obligation",
      description: row["description"].to_s.strip,
      source_clause: row["source_clause"].to_s.strip.first(100),
      trigger_type: normalize_enum(row["trigger_type"], SideLetterObligation.trigger_types.keys, "ongoing"),
      trigger_description: row["trigger_description"].to_s.strip,
      frequency_rrule: row["frequency_rrule"].to_s.strip.presence,
      next_due_date: parse_date(row["next_due_date"]),
      owner_team: normalize_enum(row["owner_team"], SideLetterObligation::OWNER_TEAMS, nil),
      ai_confidence: row["confidence"].to_f.clamp(0.0, 1.0),
      reminder_days_before: default_reminder_days,
      extracted_by: "ai",
      review_status: "pending_review",
      legal_category: normalize_enum(row["legal_category"], SideLetterObligation.legal_categories.keys, "side_letter_obligation")
    }
  end

  # @param investment [PortfolioInvestment] source record for entity_id and sourceable link
  # @param row [Hash] LLM-extracted obligation data including legal_category
  # @return [Hash] attributes for SideLetterObligation.create!
  def portfolio_row_attributes(investment, row)
    {
      entity_id: investment.entity_id,
      sourceable: investment,
      obligation_type: normalize_enum(row["obligation_type"], SideLetterObligation.obligation_types.keys, "other"),
      legal_category: normalize_enum(row["legal_category"], SideLetterObligation.legal_categories.keys, "condition_precedent"),
      title: row["title"].to_s.strip.presence || "Untitled obligation",
      description: row["description"].to_s.strip,
      source_clause: row["source_clause"].to_s.strip.first(100),
      trigger_type: normalize_enum(row["trigger_type"], SideLetterObligation.trigger_types.keys, "ongoing"),
      trigger_description: row["trigger_description"].to_s.strip,
      frequency_rrule: row["frequency_rrule"].to_s.strip.presence,
      next_due_date: parse_date(row["next_due_date"]),
      owner_team: normalize_enum(row["owner_team"], SideLetterObligation::OWNER_TEAMS, nil),
      ai_confidence: row["confidence"].to_f.clamp(0.0, 1.0),
      reminder_days_before: default_reminder_days,
      extracted_by: "ai",
      review_status: "pending_review"
    }
  end

  # Splits the +investment_doc_tag+ config value into an array of lowercase
  # tag strings. Supports comma-separated tags (e.g. "SHA, SSA" → ["sha", "ssa"]).
  #
  # @param agent_or_record [SupportAgent, #json_fields] agent record or config source
  # @return [Array<String>] lowercase tag strings, empty if none configured
  def split_investment_doc_tags(agent_or_record)
    raw = (agent_or_record&.json_fields || {})["investment_doc_tag"].to_s.strip.downcase
    raw.split(",").map(&:strip).compact_blank
  end

  # Builds a SQL condition array for matching any of the given tags against
  # +documents.tag_list+. Uses LOWER + COALESCE + LIKE OR chains, identical
  # to the SLO path's +TAG_PATTERNS+ approach.
  #
  # @param tags [Array<String>] lowercase tag strings to match
  # @return [Array] ActiveRecord-compatible condition: [sql_string, **binds]
  def investment_tag_conditions(tags)
    conditions = tags.each_with_index.map { |_t, i| "LOWER(COALESCE(documents.tag_list, '')) LIKE :tag_#{i}" }
    binds = tags.each_with_index.to_h { |t, i| [:"tag_#{i}", "%#{t}%"] }
    [conditions.join(" OR "), **binds]
  end

  def default_reminder_days
    days = (@support_agent.json_fields || {})["default_reminder_days_before"].to_i
    days.positive? ? days : 7
  end

  def normalize_enum(value, allowed, fallback)
    v = value.to_s.strip.downcase
    allowed.include?(v) ? v : fallback
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  # @param ctx [Hash] step context
  # @param count [Integer] number of new obligations created
  def report_pending(ctx, count)
    ctx[:issues][:extraction_issues] << {
      type: :pending_review,
      message: "#{count} obligation(s) awaiting counsel review",
      severity: :warning
    }
  end

  # @param ctx [Hash] step context
  def report_unchanged(ctx)
    ctx[:issues][:extraction_issues] << {
      type: :unchanged,
      message: "Extraction matched existing obligations — nothing new to review",
      severity: :success
    }
  end

  # Wraps the base class report generation with step-UI broadcasts.
  # Finalizes the report so the progress panel shows completion.
  #
  # @param ctx [Hash] step context with :support_agent_report
  # @param model [ActiveRecord::Base] the target record (commitment or investment)
  # @param support_agent [SupportAgent] the agent record
  # @return [Boolean] true if report saved successfully
  # Wraps the base class report generation with step-UI broadcasts.
  # Finalizes the report and auto-redirects to the obligation matrix tab
  # after a short delay so the user sees completed steps before refresh.
  #
  # @param ctx [Hash] step context with :support_agent_report
  # @param model [ActiveRecord::Base] the target record (commitment or investment)
  # @param support_agent [SupportAgent] the agent record
  # @return [Boolean] true if report saved successfully
  def generate_progress_reports(ctx, model:, support_agent:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :generate_progress_reports) if report
    result = super
    mark_step_success(report, :generate_progress_reports, message: "Report saved") if report
    finalize_report(report, status: :ready) if report
    # Only redirect when obligations were actually extracted; on failure the
    # user should stay on the progress panel to see the error step.
    broadcast_redirect_to_matrix(report, support_agent) if report && ctx[:extracted].present?
    result
  end

  # Broadcasts a Turbo Stream that auto-redirects to the obligation matrix
  # tab after a 2-second delay, so the user sees the completed steps before
  # the page refreshes with the extracted obligations.
  #
  # @param report [SupportAgentReport] the completed report
  # @param support_agent [SupportAgent] the agent record for URL generation
  # @return [void]
  def broadcast_redirect_to_matrix(report, support_agent)
    url = Rails.application.routes.url_helpers.support_agent_path(support_agent, tab: "obligations")
    Turbo::StreamsChannel.broadcast_append_to(
      "support_agent_report_#{report.id}",
      target: "progress_panel_#{report.id}",
      html: "<script>setTimeout(function() { Turbo.visit('#{url}') }, 2000)</script>"
    )
  rescue StandardError, ScriptError => e
    Rails.logger.warn { "[SideLetterObligationAgent] Redirect broadcast failed: #{e.message}" }
  end

  # @param source_mode [Symbol] :capital_commitments or :portfolio_investments
  # @return [String] LLM prompt tailored to the document type being extracted
  def extraction_prompt(source_mode = :capital_commitments)
    if source_mode == :portfolio_investments
      portfolio_extraction_prompt
    else
      commitment_extraction_prompt
    end
  end

  # @return [String] extraction prompt for side letter documents on commitments
  def commitment_extraction_prompt
    <<~PROMPT
      You are reviewing a private fund side letter between a GP and an LP. Extract every
      obligation (covenant) the letter creates — reporting requirements, fee arrangements,
      co-investment rights, notice requirements, transfer restrictions, excuse rights,
      confidentiality terms, key person provisions, MFN clauses.

      Reply strictly as a JSON array. Each element:
      {
        "obligation_type": one of ["reporting","fees","co_investment","notice","transfer","excuse","confidentiality","key_person","mfn","other"],
        "legal_category": one of ["condition_precedent","condition_subsequent","side_letter_obligation"] — CP = must be satisfied before an event can occur; CS = ongoing obligation where breach triggers consequences; SLO = standard promise/covenant,
        "title": short label (e.g. "Quarterly ESG report"),
        "description": the obligation in full, paraphrased faithfully,
        "source_clause": the section reference (e.g. "Section 4.3(b)") — REQUIRED; omit the item entirely if you cannot cite it,
        "trigger_type": one of ["calendar_event","one_time","fund_event","deal_event","status_change","ongoing"],
        "trigger_description": when/how it triggers (e.g. "Within 45 days of each quarter-end"),
        "frequency_rrule": iCal RRULE for recurring calendar obligations (e.g. "FREQ=QUARTERLY;INTERVAL=1"), else null,
        "next_due_date": next concrete deadline as YYYY-MM-DD if determinable, else null,
        "owner_team": best-fit team, one of ["ir","finance","legal","deal_team","operations"], else null,
        "confidence": 0.0-1.0 how certain you are this is a real obligation
      }

      Do not invent obligations. Only include items you can cite to a specific clause.
    PROMPT
  end

  # Returns the extraction prompt for investment agreements (SHA/SSA) on
  # portfolio investments. Only extracts conditions precedent (CP) and
  # conditions subsequent (CS) — general covenants and standard obligations
  # are deliberately excluded so the output stays focused on trackable
  # pre-/post-closing conditions.
  #
  # @return [String] LLM prompt scoped to CP/CS extraction only
  def portfolio_extraction_prompt
    <<~PROMPT
      You are a legal analyst reviewing transaction documents relating to an investment,
      acquisition, subscription, or transfer of securities — including Shareholders
      Agreements (SHA), Share Subscription Agreements (SSA), Share Purchase Agreements
      (SPA), Investment Agreements, and related schedules, annexures and exhibits.

      Extract every genuine Condition Precedent (CP) and Condition Subsequent (CS).
      Be exhaustive in finding CPs and CSs, but conservative in classification.
      Do not classify an obligation as CP or CS merely because it is important,
      time-bound, or actionable.

      ## Classification test

      ### Condition Precedent (CP)
      Classify as condition_precedent only where the agreement requires the matter to
      be completed, satisfied, delivered, obtained, complied with, confirmed, or waived
      BEFORE Closing/Completion or as a condition to a party being required to complete.

      CPs may appear in dedicated CP clauses, Closing clauses, schedules of closing
      conditions, or anywhere the legal effect is that completion is conditional on
      that requirement. The document need not call it a "Condition Precedent."

      Typical CPs include:
      - Board, shareholder, or investor approvals
      - Amendment or adoption of constitutional documents
      - Execution of transaction documents or employment/IP/founder agreements
      - Third-party, regulatory, governmental, or competition/antitrust approvals
      - Compliance with ROFR, ROFO, pre-emption, tag, drag or other transfer rights
      - Waiver of contractual or statutory rights
      - KYC/AML completion required before Closing
      - Evidence of title to shares or securities
      - Removal or release of encumbrances
      - Conversion, subdivision, or reclassification of securities before Closing
      - Creation or increase of authorised share capital; reservation of shares
      - Receipt of valuation reports, legal opinions, or certificates
      - Lender or counterparty consents
      - Repayment or restructuring of identified debt required before Closing
      - Settlement of identified litigation or liabilities required before Closing
      - Completion of specified corporate restructuring
      - Employee/founder actions required before Closing
      - IP transfers or registrations required before Closing
      - No material adverse change conditions
      - No injunction, prohibition or illegality conditions
      - Warranties being true at Closing (bring-down conditions)
      - Delivery of specified documents or certificates required before Closing

      ### Condition Subsequent (CS)
      Classify as condition_subsequent only where the agreement requires a specific
      action, filing, approval, registration, or deliverable to be completed AFTER
      Closing, usually within a specified period, and the obligation is directly
      connected to completing, perfecting, or implementing the transaction.

      Typical CSs include:
      - Post-Closing statutory filings with registrar or governmental authority
      - Updating registers of members, securities holders, or statutory registers
      - Issuing share certificates; depository or dematerialisation entries
      - Stamping or registration of transaction documents
      - Filing amended constitutional documents
      - Post-Closing regulatory notifications
      - Post-Closing tax filings or certificates arising from the transaction
      - Completion of registrations that could not be completed before Closing
      - Perfection or registration of security interests
      - Approvals expressly permitted to be obtained after Closing
      - Corporate actions or document deliveries expressly deferred until after Closing
      - Rectification of identified diligence issues required after Closing

      ## What NOT to extract — these are NOT CP or CS:
      Do not extract merely because an obligation has a deadline, occurs before or
      after Closing, is important, or has breach consequences. The key test: is it
      part of the transaction completion framework?

      Exclude:
      - Information rights, monthly/quarterly/annual reporting, financial statements
      - Board information or inspection rights
      - Reserved matter consent rights
      - Affirmative or negative covenants governing future business conduct
      - Ongoing regulatory compliance
      - Confidentiality, non-compete, non-solicit, founder lock-ins
      - Transfer restrictions applicable to future transfers
      - ROFR/ROFO/tag/drag for future transfers (unless a pre-Closing condition)
      - Anti-dilution rights, pre-emption for future issuances
      - Liquidation preference, exit rights
      - Indemnities, representations, warranties, warranty survival periods
      - Limitation of liability provisions
      - Fee or expense allocation, ordinary payment obligations
      - Ordinary tax covenants, insurance covenants, key-person obligations
      - MFN rights, co-investment rights, notice procedures
      - Governance rights, employment obligations of an ongoing nature
      - General obligations to comply with applicable law
      - Definitions, interpretation clauses, recitals
      - Boilerplate: governing law, jurisdiction, arbitration, severability
      - Amendment/waiver mechanics (extract the underlying CP, not the procedure)
      - Transaction descriptions ("Seller agrees to sell" is not a CP)
      - Generic waiver language ("Investor may waive any CP in writing")

      ## Compound clauses
      Where one clause contains multiple independently satisfiable CPs or CSs,
      create separate items for each. Do not combine unrelated obligations.

      ## Schedules and annexures
      Review the ENTIRE document — all schedules, annexures, exhibits, closing
      checklists, and completion mechanics. Do not stop after the first CP/CS clause.

      ## Closing deliverables
      Items under "Closing Deliverables" may be CPs if delivery is a condition to
      Closing, or may be simultaneous exchange mechanics. Classify based on legal
      effect, not heading.

      ## Dates and deadlines
      Capture timing as stated ("prior to Closing", "within 15 days following Closing").
      Set next_due_date only where a concrete YYYY-MM-DD can be calculated from dates
      in the document. If Closing has not occurred, return null.

      ## Confidence scoring
      - 0.95-1.00: expressly labelled CP/CS with clear timing
      - 0.85-0.94: not labelled but clearly a pre-Closing condition or post-Closing completion item
      - 0.70-0.84: strongly implied but wording less explicit
      - Below 0.70: generally do not extract

      ## Output format
      Reply strictly as a JSON array. Each element:
      {
        "obligation_type": one of ["reporting","fees","co_investment","notice","transfer","excuse","confidentiality","key_person","mfn","other"],
        "legal_category": one of ["condition_precedent","condition_subsequent"] — ONLY these two values,
        "title": short action-oriented label (e.g. "Board approval for share transfer"),
        "description": faithful paraphrase of what must be done, obtained, or satisfied,
        "source_clause": exact clause/section/schedule reference — REQUIRED; omit item if you cannot cite it,
        "trigger_type": one of ["calendar_event","one_time","fund_event","deal_event","status_change","ongoing"],
        "trigger_description": when/how it triggers (e.g. "Prior to Closing", "Within 30 days after Closing"),
        "frequency_rrule": iCal RRULE for genuinely recurring obligations, else null,
        "next_due_date": YYYY-MM-DD if determinable from the document, else null,
        "owner_team": one of ["ir","finance","legal","deal_team","operations"], else null,
        "confidence": 0.0-1.0 (classification correctness, not clause clarity)
      }

      Be exhaustive — extract every CP and CS from every clause and schedule.
      Do not invent obligations. Only include items you can cite to a specific clause.
      If no qualifying CP or CS exists, return [].
    PROMPT
  end

  def parse_response(raw)
    text = if raw.is_a?(RubyLLM::Message)
             raw.content.to_s
           else
             raw.to_s
           end
    text = text.strip.sub(/\A```(?:json)?/i, "").sub(/```\z/, "").strip
    parsed = JSON.parse(text)
    # Accept both a bare array and {"obligations": [...]}
    parsed.is_a?(Hash) ? Array(parsed["obligations"]) : Array(parsed)
  end
end
