# frozen_string_literal: true

# NoteSummarizerAgent generates an LLM-powered summary of investor notes
# for a configured monthly or quarterly period. It runs per-investor, saves
# a SupportAgentReport with the summary text, and supports batch/scheduled runs.
#
# Configuration via json_fields (FormType tag: "NoteSummarizerAgent"):
#   summary_period — "Month" or "Quarter" (default "Quarter")
#   tag_filter     — comma-separated tags to restrict which notes are included (blank = all)
#   available_tags — comma-separated list of canonical tags the LLM may assign to untagged notes
#
# @see SupportAgentService for base class step helpers (generate_progress_reports, enabled?, etc.)
class NoteSummarizerAgent < SupportAgentService
  DESCRIPTION = "Generates LLM-based summaries of investor notes on a monthly or quarterly schedule. Auto-tags untagged notes before summarising.".freeze

  LONG_DESCRIPTION = <<~DESC.freeze
    Generates an LLM-powered summary of investor notes for each investor over a configured
    monthly or quarterly lookback period. Runs as a batch across all investors for the entity.

    Steps:
    • Auto-Tag Notes — finds untagged notes in the period and asks the LLM to assign tags in
      one batch call. Uses available_tags vocabulary when set; otherwise the LLM uses its own
      judgement for concise, fund-relevant tags. Toggleable via auto_tag_notes (Yes/No).
    • Collect Notes — queries notes for the investor within the period, applying tag_filter if
      set. Always excludes notes already tagged "summary" to prevent re-summarising prior runs.
    • Generate Summary — formats collected notes and sends to the LLM. Produces three sections:
      Key Themes, Action Items (or "None identified"), and Relationship Status (Active /
      In Discussion / Dormant) with a one-sentence justification.
    • Save Note — writes the summary back as a Note on the investor tagged summary,quarter or
      summary,month. Idempotent — overwrites the existing summary for the same period date.
    • Save Report — persists a SupportAgentReport with summary_text, note_count, period_label,
      period_start, period_end. Investors with zero qualifying notes are saved as "skipped"
      with no LLM call made (saves cost).

    Config: summary_period (Month/Quarter), tag_filter (comma-separated tags to restrict
    which notes are collected), auto_tag_notes (Yes/No), available_tags (tag vocabulary).
  DESC

  # Human-readable labels shown in the step progress panel
  STEP_LABELS = {
    initialize_agent:          "Initialize",
    tag_untagged_notes:        "Auto-Tag Notes",
    collect_notes:             "Collect Notes",
    generate_summary:          "Generate Summary",
    save_summary_as_note:      "Save Note",
    generate_progress_reports: "Save Report"
  }.freeze

  step :initialize_agent
  step :tag_untagged_notes
  step :collect_notes
  step :generate_summary
  step :save_summary_as_note
  step :generate_progress_reports

  # Returns all investors for the entity. Callers can narrow this by
  # passing a single Investor (adhoc) or scoping the relation before calling process_batch.
  def targets(entity_id)
    if entity_id.is_a?(Investor) || entity_id.is_a?(ActiveRecord::Base)
      [entity_id]
    else
      Investor.where(entity_id: entity_id)
    end
  end

  # Batch processor — shared by adhoc and scheduled runs.
  # Mirrors the pattern in PortfolioScoringAgent: sequential processing,
  # optional batch summary notification (suppressed for :scheduled mode).
  #
  # @param support_agent_id [Integer]
  # @param targets [Array, ActiveRecord::Relation] Investor records to process
  # @param user_id [Integer, nil] nil for scheduled runs
  # @param entity_id [Integer]
  # @param execution_mode [Symbol] :adhoc_batch or :scheduled
  def self.process_batch(support_agent_id:, targets:, user_id:, entity_id:, with_steps: false, execution_mode: :adhoc_batch) # rubocop:disable Lint/UnusedMethodArgument
    support_agent = SupportAgent.find(support_agent_id)

    # Preload notes to avoid N+1 when iterating investors sequentially
    targets = targets.includes(:notes) if targets.respond_to?(:includes)

    successes = []
    errors    = []

    targets.to_a.each do |target|
      begin
        # One Trailblazer call per investor — each gets its own ctx and report
        support_agent.agent.wtf?(
          support_agent_id: support_agent_id,
          target:           target,
          user_id:          user_id,
          entity_id:        entity_id,
          batch_mode:       true
        )
        successes << { id: target.id, name: target.try(:investor_name) || target.try(:name) || "ID=#{target.id}" }
      rescue StandardError => e
        Rails.logger.error { "[NoteSummarizerAgent] process_batch error for Target ID=#{target.id}: #{e.message}" }
        Rails.logger.error { e.backtrace.join("\n") }
        errors << {
          target_id:   target.id,
          target_name: target.try(:investor_name) || target.try(:name) || "ID=#{target.id}",
          error:       e.message
        }
      end
    end

    # Batch summary notification — suppressed for scheduled runs (no user to notify)
    if execution_mode != :scheduled
      begin
        batch_target_type = targets.first.class.name if targets.any?
        SupportAgentJob.new.send(:send_batch_summary, support_agent, successes, errors, user_id, batch_target_type) if defined?(SupportAgentJob)
      rescue StandardError => e
        Rails.logger.error { "[NoteSummarizerAgent] process_batch: failed to send batch summary: #{e.message}" }
      end
    end

    { successes: successes, errors: errors }
  end

  private

  # Sets up investor context, computes the period date range from summary_period, and
  # initialises the issues hash. Returns false if the agent is disabled (halts the pipeline).
  #
  # @param ctx [Hash] Trailblazer execution context
  # @param target [Investor] the investor being processed in this run
  def initialize_agent(ctx, target: nil, **)
    super # loads @support_agent and ctx[:llm] via base class

    investor = target
    ctx[:investor] = investor

    # Derive lookback window from the summary_period field ("Month" or "Quarter")
    period = @support_agent.json_fields["summary_period"].presence || "Quarter"
    ctx[:period_label] = period

    case period.downcase
    when "month"
      # Summarise the previous calendar month so the period is always complete
      ctx[:period_start] = Date.today.prev_month.beginning_of_month
      ctx[:period_end]   = Date.today.prev_month.end_of_month
    else
      # Default to previous calendar quarter using the same helper as PortfolioCompanyAgent
      prev_quarter_last_day = Date.today.beginning_of_quarter - 1.day
      ctx[:period_start]    = prev_quarter_last_day.beginning_of_quarter
      ctx[:period_end]      = prev_quarter_last_day.end_of_quarter
    end

    # Issues hash follows the same {key => Array<{type:, message:, severity:}>} contract
    # expected by the base class generate_progress_reports
    ctx[:issues] = { tagging_issues: [], note_issues: [], summary_issues: [] }

    Rails.logger.info do
      "[NoteSummarizerAgent] Initialized investor=#{investor.id} period=#{period} " \
      "(#{ctx[:period_start]}..#{ctx[:period_end]})"
    end

    @support_agent.enabled?
  end

  # Finds untagged notes in the period and asks the LLM to assign tags.
  # When available_tags is configured the LLM is constrained to that vocabulary;
  # when blank it uses its own judgement to pick appropriate tags.
  # The step is skipped entirely when auto_tag_notes is set to "No".
  #
  # The LLM receives all untagged notes in a single call (not one call per note)
  # and returns a JSON array mapping note IDs to tag strings.
  #
  # @param ctx [Hash] execution context; reads :investor, :period_start, :period_end
  def tag_untagged_notes(ctx, investor: nil, **)
    # Honour the enable/disable toggle — default on if the field is absent
    unless enabled?("auto_tag_notes")
      ctx[:issues][:tagging_issues] << {
        type: :info, message: "Auto-tagging disabled — skipped", severity: :success
      }
      return true
    end

    # Resolve the configurable tag vocabulary; blank = free-form LLM judgement
    available_tags = @support_agent.json_fields["available_tags"]
                                   .to_s
                                   .split(",")
                                   .map(&:strip)
                                   .reject(&:blank?)

    # Load only notes that have no tags yet within the period — no need to re-tag existing ones
    untagged = Note
                 .where(investor: investor, entity: @support_agent.entity)
                 .where(on: ctx[:period_start]..ctx[:period_end])
                 .where(tags: [nil, ""])
                 .with_all_rich_text

    untagged_notes = untagged.to_a

    if untagged_notes.empty?
      ctx[:issues][:tagging_issues] << {
        type: :info, message: "No untagged notes in period — skipped", severity: :success
      }
      return true
    end

    Rails.logger.info { "[NoteSummarizerAgent] Auto-tagging #{untagged_notes.size} untagged notes for investor=#{investor.id}" }

    # Format each untagged note for the LLM in a compact, ID-keyed block
    note_blocks = untagged_notes.map do |note|
      body = note.details.to_plain_text.strip.truncate(500)
      "[note_id=#{note.id}] [#{note.on}]\n#{body}"
    end.join("\n\n---\n\n")

    prompt = build_tagging_prompt(available_tags, note_blocks)

    response    = ctx[:llm].ask(prompt)
    raw_content = extract_text_content(response)

    # Extract the JSON array from the LLM response; it may be wrapped in a code fence
    json_match = raw_content.match(/```json\s*(\[.+?\])\s*```/m) ||
                 raw_content.match(/```\s*(\[.+?\])\s*```/m) ||
                 raw_content.match(/(\[.+\])/m)

    unless json_match
      Rails.logger.warn { "[NoteSummarizerAgent] LLM returned no parseable JSON for tagging — skipping" }
      ctx[:issues][:tagging_issues] << {
        type: :info, message: "Auto-tagging skipped — LLM response was not parseable", severity: :success
      }
      return true
    end

    assignments = JSON.parse(json_match[1])
    tagged_count = 0

    Chewy.strategy(:atomic) do
      assignments.each do |assignment|
        note_id  = assignment["id"].to_i
        new_tags = assignment["tags"].to_s.strip
        next if new_tags.blank?

        # Only update notes that are actually in our untagged set — ignore any hallucinated IDs
        note = untagged_notes.find { |n| n.id == note_id }
        next unless note

        note.update!(tags: new_tags)
        tagged_count += 1
        Rails.logger.info { "[NoteSummarizerAgent] Tagged note #{note_id} with: #{new_tags}" }
      end
    end

    ctx[:issues][:tagging_issues] << {
      type: :info,
      message: "Auto-tagged #{tagged_count} of #{untagged_notes.size} untagged note(s)",
      severity: :success
    }
    true
  rescue StandardError => e
    # Soft-fail — tagging is best-effort, must not block the summary
    Rails.logger.error { "[NoteSummarizerAgent] Auto-tagging failed: #{e.message}" }
    ctx[:issues][:tagging_issues] << {
      type: :info, message: "Auto-tagging failed (#{e.message}) — continuing without tags", severity: :success
    }
    true
  end

  # Queries Notes for the investor within the period, optionally filtering by tags.
  # Stores the notes array and count in ctx for the next step.
  #
  # @param ctx [Hash] execution context; writes :notes and :note_count
  # @param investor [Investor] current target
  def collect_notes(ctx, investor: nil, **)
    # Scope to the investor + entity so notes from other entities are never leaked.
    # Exclude auto-generated summary notes (tagged "summary") so they are never
    # included in future summaries — they exist only for reference.
    notes = Note
              .where(investor: investor, entity: @support_agent.entity)
              .where(on: ctx[:period_start]..ctx[:period_end])
              .where("tags NOT REGEXP ? OR tags IS NULL OR tags = ''", "(^|,)summary(,|$)")
              .with_all_rich_text # eager-loads the ActionText body in one query

    # Optional tag filter: only include notes whose tags column matches at least one tag
    tag_filter = @support_agent.json_fields["tag_filter"]
                               .to_s
                               .split(",")
                               .map(&:strip)
                               .reject(&:blank?)

    if tag_filter.any?
      # REGEXP matches any note containing at least one of the configured tags
      tag_pattern = tag_filter.map { |t| Regexp.escape(t) }.join("|")
      notes = notes.where("tags REGEXP ?", tag_pattern)
      Rails.logger.info { "[NoteSummarizerAgent] Tag filter applied: #{tag_filter.inspect}" }
    end

    ctx[:notes]      = notes.to_a
    ctx[:note_count] = ctx[:notes].size

    if ctx[:notes].empty?
      ctx[:issues][:note_issues] << {
        type: :info,
        message: "No notes found in #{ctx[:period_label]} #{ctx[:period_start].year} — skipped",
        severity: :success
      }
      Rails.logger.info { "[NoteSummarizerAgent] No notes for investor=#{investor.id} in period" }
    else
      ctx[:issues][:note_issues] << {
        type: :info,
        message: "#{ctx[:note_count]} note(s) collected for #{ctx[:period_label]} #{ctx[:period_start].year}",
        severity: :success
      }
      Rails.logger.info { "[NoteSummarizerAgent] #{ctx[:note_count]} notes collected for investor=#{investor.id}" }
    end

    true
  end

  # Formats the collected notes and calls the LLM to produce a structured summary.
  # Stores the summary text in ctx[:summary_text]. Always returns true so
  # generate_progress_reports runs even on LLM failure.
  #
  # @param ctx [Hash] execution context; reads :notes, writes :summary_text
  # @param investor [Investor] current target (used for logging)
  def generate_summary(ctx, investor: nil, **)
    # Skip LLM call when there are no notes — saves cost and avoids a meaningless request
    if ctx[:notes].empty?
      ctx[:issues][:summary_issues] << {
        type: :info,
        message: "No notes to summarize — LLM call skipped",
        severity: :success
      }
      return true
    end

    # Format each note as "[YYYY-MM-DD] (tags)\nbody" for the LLM
    formatted_notes = ctx[:notes].map do |note|
      tags_str = note.tags.presence || "no tags"
      # Strip ActionText HTML to plain text; truncate per-note to avoid huge inputs
      body = note.details.to_plain_text.strip.truncate(2000)
      "[#{note.on}] (#{tags_str})\n#{body}"
    end.join("\n\n---\n\n")

    # Guard against prompts that would blow the context window — oldest notes go first
    # by default (no ORDER BY override here), so truncating the end drops oldest content last
    if formatted_notes.length > 50_000
      formatted_notes = formatted_notes.first(50_000)
      Rails.logger.warn { "[NoteSummarizerAgent] Note text truncated to 50,000 chars for investor=#{investor.id}" }
    end

    period_desc = "#{ctx[:period_label]} #{ctx[:period_start].year}"
    prompt      = build_summary_prompt(investor.investor_name, period_desc, formatted_notes)

    Rails.logger.info { "[NoteSummarizerAgent] Sending #{formatted_notes.length} chars to LLM for investor=#{investor.id}" }

    response           = ctx[:llm].ask(prompt)
    ctx[:summary_text] = extract_text_content(response)

    ctx[:issues][:summary_issues] << {
      type: :info,
      message: "Summary generated (#{ctx[:summary_text].length} chars)",
      severity: :success
    }
    Rails.logger.info { "[NoteSummarizerAgent] Summary generated for investor=#{investor.id}" }
    true
  rescue StandardError => e
    # Soft-fail: record the error in issues so the report reflects the failure
    # without crashing the batch run for other investors
    Rails.logger.error { "[NoteSummarizerAgent] LLM call failed for investor=#{investor.id}: #{e.message}" }
    ctx[:issues][:summary_issues] << {
      type: :error,
      message: "Summary generation failed: #{e.message}",
      severity: :blocking
    }
    true
  end

  # Writes the generated summary back as a Note on the investor so it is visible
  # in the standard notes feed. The note is tagged "summary,quarterly" (or "summary,monthly")
  # so that future runs can exclude it via the collect_notes REGEXP filter.
  #
  # One summary note per period — idempotent: if a summary note with these tags and
  # `on` date already exists for this investor it is overwritten rather than duplicated.
  #
  # @param ctx [Hash] execution context; reads :summary_text, :period_label, :period_start
  # @param investor [Investor] note owner
  def save_summary_as_note(ctx, investor: nil, **)
    # Skip if there is nothing to write (no notes in period or LLM failure)
    unless ctx[:summary_text].present?
      ctx[:issues][:summary_issues] << {
        type: :info, message: "No summary to save as note — skipped", severity: :success
      }
      return true
    end

    # Tag format: "summary,quarterly" or "summary,monthly" — lowercase to match existing convention
    period_tag = ctx[:period_label].to_s.downcase
    tags       = "summary,#{period_tag}"

    # Use the last day of the period as the note date so it sorts naturally in the notes feed
    note_date = ctx[:period_end]

    # Find an existing summary note for this period to overwrite rather than duplicate
    existing = Note.where(investor: investor, entity: @support_agent.entity, on: note_date)
                   .where("tags REGEXP ?", "(^|,)summary(,|$)")
                   .first

    note = existing || Note.new(
      investor: investor,
      entity:   @support_agent.entity,
      user:     User.where(entity_id: @support_agent.entity_id).first, # system note — use first entity user
      on:       note_date
    )

    note.tags    = tags
    note.details = ctx[:summary_text]

    Chewy.strategy(:atomic) { note.save! }

    ctx[:issues][:summary_issues] << {
      type: :info,
      message: "#{existing ? 'Updated' : 'Created'} summary note (ID=#{note.id}) tagged '#{tags}'",
      severity: :success
    }
    Rails.logger.info { "[NoteSummarizerAgent] Summary note #{note.id} saved for investor=#{investor.id}" }
    true
  rescue StandardError => e
    # Soft-fail — note write failure must not block the report save
    Rails.logger.error { "[NoteSummarizerAgent] Failed to save summary note for investor=#{investor.id}: #{e.message}" }
    ctx[:issues][:summary_issues] << {
      type: :info, message: "Could not save summary as note: #{e.message}", severity: :success
    }
    true
  end

  # Delegates to the base class to persist ctx[:issues] as a SupportAgentReport,
  # then augments the report's json_fields with summary-specific metadata that
  # the base class doesn't know about.
  #
  # @param ctx [Hash] execution context; reads :summary_text, :note_count, period fields
  # @param investor [Investor] used as the report owner (model: arg to base class)
  # @param support_agent [SupportAgent] current agent record
  def generate_progress_reports(ctx, investor: nil, support_agent:, **)
    # Base class writes ctx[:issues] into json_fields and persists the report
    super(ctx, model: investor, support_agent: support_agent)

    # Merge summary payload into the same report — base class already saved it,
    # so we load the record from ctx and do a second targeted update
    report = ctx[:support_agent_report]
    return true unless report

    report.json_fields = (report.json_fields || {}).merge(
      "summary_text"  => ctx[:summary_text].to_s,
      "note_count"    => ctx[:note_count].to_i,
      "period_label"  => ctx[:period_label],
      "period_start"  => ctx[:period_start]&.iso8601,
      "period_end"    => ctx[:period_end]&.iso8601
    )
    # MySQL doesn't detect JSON field mutations automatically — must mark dirty
    report.json_fields_will_change!
    report.save!

    true
  end

  # Builds the tagging prompt. All untagged notes are sent in one call to minimise LLM requests.
  # When available_tags is present the LLM is constrained to that vocabulary;
  # when empty it may choose any concise, lowercase tags appropriate for fund manager notes.
  #
  # @param available_tags [Array<String>] canonical tag list (may be empty)
  # @param note_blocks [String] pre-formatted note text with [note_id=N] markers
  # @return [String]
  def build_tagging_prompt(available_tags, note_blocks)
    tag_constraint = if available_tags.any?
                       "Available tags (use ONLY these, no others): #{available_tags.join(', ')}"
                     else
                       "Choose concise, lowercase tags appropriate for fund manager notes (e.g. call, meeting, kpi, risk, hiring, fundraising). Use your best judgement."
                     end

    <<~PROMPT
      You are a fund manager's assistant. Your task is to assign tags to investor notes.

      #{tag_constraint}

      For each note below, return a JSON array where each element has:
        - "id": the note_id integer from the [note_id=N] marker
        - "tags": a comma-separated string of one or more matching tags

      Return ONLY the JSON array, no explanation.

      === NOTES ===
      #{note_blocks}
    PROMPT
  end

  # Builds the prompt sent to the LLM. Keeps the instruction set minimal and explicit
  # to prevent the model from hallucinating content not present in the notes.
  #
  # @param investor_name [String]
  # @param period [String] human label like "Quarter 2025"
  # @param notes_text [String] pre-formatted note blocks
  # @return [String] full prompt
  def build_summary_prompt(investor_name, period, notes_text)
    <<~PROMPT
      You are a fund manager's assistant. Below are investor notes for #{investor_name} from #{period}.

      Summarize them into three clearly labeled sections:
      1. **Key Themes** — recurring topics and discussion points (bullet points)
      2. **Action Items** — specific follow-ups or commitments identified (bullet points, or "None identified")
      3. **Relationship Status** — one of: Active / In Discussion / Dormant, with one sentence of justification

      Rules:
      - Be concise. Do not invent information not present in the notes.
      - If notes are sparse, acknowledge that in your summary.
      - Output plain prose — no markdown code fences.

      === NOTES ===
      #{notes_text}
    PROMPT
  end

  # Extracts plain text from an LLM response object.
  # Mirrors the same helper in PortfolioScoringAgent to handle both string
  # responses and RubyLLM::Content objects consistently.
  #
  # @param response [String, RubyLLM::Message] the raw LLM response
  # @return [String]
  def extract_text_content(response)
    return response.to_s unless response.respond_to?(:content)

    content = response.content
    content.is_a?(RubyLLM::Content) ? content.text : content.to_s
  end
end
