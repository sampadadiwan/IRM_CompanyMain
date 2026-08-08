# frozen_string_literal: true

# Extracts obligations ("covenants") from side letter documents attached to
# capital commitments, and enforces their due dates.
#
# Two run modes (mirrors PortfolioCompanyAgent's mode dispatch):
#   - Extraction (manual single/batch): locate the side letter PDF on each
#     commitment by the configured document label, LLM-extract structured
#     obligations, and save them as SideLetterObligation rows in
#     pending_review. NOTHING becomes active without counsel approval
#     (ObligationApprove) — extraction never creates tasks or alerts.
#   - Enforcement (scheduled daily): delegates to ObligationEnforcement, which
#     alerts owners on upcoming / due-today / overdue obligation tasks.
#
# Config in SupportAgent.json_fields (via form custom fields):
#   side_letter_doc_label       — document name identifying a side letter (default "Side Letter")
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

  # Extraction targets: commitments that actually have the configured side
  # letter document. Accepts a single commitment (adhoc single run) or an
  # entity_id (batch/scheduled resolution).
  def targets(entity_id)
    return [entity_id] if entity_id.is_a?(ActiveRecord::Base)

    agent_record = SupportAgent.where(entity_id: entity_id, agent_type: "SideLetterObligationAgent").last
    label = self.class.doc_label(agent_record)
    CapitalCommitment.where(entity_id: entity_id)
                     .joins(:documents)
                     .where(documents: { name: label })
                     .distinct
  end

  def self.doc_label(support_agent)
    ((support_agent&.json_fields || {})["side_letter_doc_label"]).presence || DEFAULT_DOC_LABEL
  end

  def self.config_issues(support_agent)
    issues = []
    fields = support_agent.json_fields || {}
    if fields["side_letter_doc_label"].to_s.strip.blank?
      issues << "'side_letter_doc_label' is not set — falling back to '#{DEFAULT_DOC_LABEL}'. Set it to the document name your side letters are uploaded under."
    end
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

  private

  def initialize_agent(ctx, target:, **)
    super
    ctx[:commitment] = target
    ctx[:model] = target
    ctx[:issues] = { extraction_issues: [] }
    true
  end

  def locate_side_letter(ctx, commitment:, **)
    label = self.class.doc_label(@support_agent)
    ctx[:side_letter_doc] = commitment.documents.where(name: label).order(:id).last

    if ctx[:side_letter_doc].nil?
      # Info, not blocking — not every LP negotiates a side letter
      ctx[:issues][:extraction_issues] << {
        type: :no_side_letter,
        message: "No document named '#{label}' on this commitment — nothing to extract",
        severity: :info
      }
    end
    true
  end

  def extract_obligations(ctx, **)
    ctx[:extracted] = []
    doc = ctx[:side_letter_doc]
    return true if doc.nil?

    raw = ctx[:llm].ask(extraction_prompt, with: [doc.file.url])
    rows = parse_response(raw)

    # Source-clause citation is mandatory: a row the LLM cannot cite is not
    # surfaced at all (spec'd guard against hallucinated obligations).
    cited, uncited = rows.partition { |r| r["source_clause"].to_s.strip.present? }
    if uncited.any?
      ctx[:issues][:extraction_issues] << {
        type: :discarded,
        message: "#{uncited.size} extracted item(s) had no source clause citation and were discarded",
        severity: :warning
      }
    end

    ctx[:extracted] = cited
    true
  rescue StandardError => e
    Rails.logger.error("[SideLetterObligationAgent] Extraction failed for Document ID=#{doc&.id}: #{e.message}")
    ctx[:issues][:extraction_issues] << {
      type: :extraction_failed,
      message: "Extraction failed: #{e.message}",
      severity: :blocking
    }
    true
  end

  def upsert_obligations(ctx, commitment:, **)
    doc = ctx[:side_letter_doc]
    return true if doc.nil? || ctx[:extracted].blank?

    side_letter = SideLetter.find_or_create_by!(capital_commitment: commitment, document: doc) do |sl|
      sl.entity_id = commitment.entity_id
    end
    # Any prior obligations mean this is a re-extraction: new/changed rows are
    # flagged as deltas so counsel reviews the diff, never a silent overwrite.
    re_extraction = side_letter.side_letter_obligations.exists?

    created = 0
    ctx[:extracted].each do |row|
      created += 1 if upsert_row(side_letter, row, re_extraction)
    end

    if created.positive?
      side_letter.update!(extraction_status: "ai_extracted")
      ctx[:issues][:extraction_issues] << {
        type: :pending_review,
        message: "#{created} obligation(s) awaiting counsel review",
        severity: :warning
      }
    else
      ctx[:issues][:extraction_issues] << {
        type: :unchanged,
        message: "Extraction matched existing obligations — nothing new to review",
        severity: :success
      }
    end
    true
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
      review_status: "pending_review"
    }
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

  def extraction_prompt
    <<~PROMPT
      You are reviewing a private fund side letter between a GP and an LP. Extract every
      obligation (covenant) the letter creates — reporting requirements, fee arrangements,
      co-investment rights, notice requirements, transfer restrictions, excuse rights,
      confidentiality terms, key person provisions, MFN clauses.

      Reply strictly as a JSON array. Each element:
      {
        "obligation_type": one of ["reporting","fees","co_investment","notice","transfer","excuse","confidentiality","key_person","mfn","other"],
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

  def parse_response(raw)
    text = if raw.is_a?(RubyLLM::Message)
             raw.content.is_a?(RubyLLM::Content) ? raw.content.text : raw.content.to_s
           else
             raw.to_s
           end
    text = text.strip.sub(/\A```(?:json)?/i, "").sub(/```\z/, "").strip
    parsed = JSON.parse(text)
    # Accept both a bare array and {"obligations": [...]}
    parsed.is_a?(Hash) ? Array(parsed["obligations"]) : Array(parsed)
  end
end
