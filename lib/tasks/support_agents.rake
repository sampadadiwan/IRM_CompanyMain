# Rake tasks for managing SupportAgent provisioning across entities.
#
# Usage:
#   rake support_agents:setup[ENTITY_ID]
#     — Idempotently creates/updates all FormTypes, custom fields, and SupportAgent
#       records for the given entity. Safe to re-run after adding new fields or agents.
#
#   rake support_agents:clone[TARGET_ENTITY_ID]
#   rake support_agents:clone[TARGET_ENTITY_ID,SOURCE_ENTITY_ID]   # defaults source to 157
#     — Clones a fully configured source entity's agents to a new target entity.
#       Run setup on the source first, then clone to others.

DEFAULT_LLM_MODEL = "gemini-3-flash-preview"

# Extraction rule templates for KycDocExtractorAgent.
# Applied dynamically at setup time, keyed by the entity's actual KYC FormType IDs.
KYC_EXTRACTOR_BASE_RULES = [
  { "doc_label" => "Upload Tax ID",       "prompt" => "Extract the PAN number from this document. Return only the 10-character alphanumeric PAN (e.g. ABCDE1234F). No explanation.", "target_field" => "PAN" },
  { "doc_label" => "Upload Address Proof","prompt" => "Extract the full permanent address from this document. Return only the address as plain text, no labels or explanation.",    "target_field" => "address" }
].freeze

# IndividualKyc/Default also extracts the investor's full name from the Tax ID document.
KYC_EXTRACTOR_FULL_NAME_RULE = {
  "doc_label" => "Upload Tax ID", "prompt" => "Extract the Full name from the document", "target_field" => "full_name"
}.freeze

# ---------------------------------------------------------------------------
# FormType + field definitions (entity-agnostic; IDs are resolved at runtime)
# ---------------------------------------------------------------------------
SUPPORT_AGENT_FORM_CONFIGS = [
  # ── Extend existing agents (FormType already provisioned by the app) ───────
  {
    tag: "KycOnboardingAgent",
    extend_only: true,  # FormType already exists; only add/update fields
    fields: [
      { name: "check_expiry",
        field_type: "Select", label: "Check KYC expiry status", meta_data: "Yes,No", position: 8,
        help_text: "When Yes, checks the KYC record's expiry_date and adds a blocking issue if it " \
                   "is already expired, or a warning if within any expiry_warning_days threshold." },
      { name: "expiry_warning_days",
        field_type: "TextField", label: "Expiry warning thresholds (days)", meta_data: "", position: 9,
        help_text: "Comma-separated day counts before expiry that trigger a warning, e.g. '60,30,15'. " \
                   "When days_remaining falls at or below any threshold an expiry-alert email is sent. " \
                   "Leave blank to disable advance warnings (only expired records are flagged)." }
    ]
  },
  {
    tag: "PortfolioCompanyAgent",
    extend_only: true,
    fields: [
      { name: "send_kpi_reminder",
        field_type: "Select", label: "Send KPI submission reminder", meta_data: "Yes,No", position: 7,
        help_text: "When Yes, sends a reminder email to the portfolio company when KPIs are overdue " \
                   "for the current period. Emails are only fired on the specific days-elapsed values " \
                   "configured in 'Reminder days', preventing duplicate sends across daily runs." },
      { name: "reminder_days",
        field_type: "TextField", label: "Reminder days (days elapsed in period)", meta_data: "", position: 8,
        help_text: "Comma-separated number of days elapsed since the period started on which to send " \
                   "a reminder, e.g. '7,14,21'. The agent checks today's elapsed day count against this " \
                   "list — no email fires on days not in the list. A reminder already sent today is skipped." }
    ]
  },

  # ── New agent FormTypes (created when missing) ─────────────────────────────
  {
    tag: "KycDocExtractorAgent",
    agent: {
      name:       "KYC Doc Extractor",
      with_steps: false,
      json_fields: {
        "overwrite_mode"   => "blank_only",
        "extraction_rules" => {}   # populated dynamically by the setup task from the entity's KYC FormTypes
      }
      # No schedule — triggered on-demand during KYC document upload
    },
    # All runtime config (overwrite_mode + extraction_rules) is managed via the
    # dedicated _kyc_doc_extractor_config partial; no FormCustomField records needed.
    fields: []
  },
  {
    tag: "DistributionReadinessAgent",
    agent: {
      name:       "Distribution Readiness",
      with_steps: true,
      json_fields: {
        "check_kyc"            => "Yes",
        "check_net_payable"    => "Yes",
        "check_docs_generated" => "Yes",
        "check_docs_approved"  => "Yes",
        "check_bank_details"   => "Yes"
      }
    },
    fields: [
      { name: "check_kyc",
        field_type: "Select", label: "Check investor KYC", meta_data: "Yes,No", position: 1,
        help_text: "When Yes, verifies the investor has a completed KYC record before the " \
                   "distribution payment is released. Marks the distribution as blocked if KYC is incomplete." },
      { name: "check_net_payable",
        field_type: "Select", label: "Check net payable computed", meta_data: "Yes,No", position: 2,
        help_text: "When Yes, verifies the distribution net payable amount has been calculated. " \
                   "Blocks payment if the amount is missing or zero." },
      { name: "check_docs_generated",
        field_type: "Select", label: "Check notices generated", meta_data: "Yes,No", position: 3,
        help_text: "When Yes, checks that distribution notice documents have been generated and " \
                   "are attached to the distribution record." },
      { name: "check_docs_approved",
        field_type: "Select", label: "Check notices approved", meta_data: "Yes,No", position: 4,
        help_text: "When Yes, verifies that the generated distribution notice documents are in an " \
                   "approved state. Blocks payment if any notice is still pending approval." },
      { name: "check_bank_details",
        field_type: "Select", label: "Check bank details on file", meta_data: "Yes,No", position: 5,
        help_text: "When Yes, verifies the investor has valid bank account details recorded. " \
                   "Blocks payment if banking information is missing or incomplete." }
    ]
  },
  {
    tag: "EsignMonitorAgent",
    agent: {
      name:       "E-Sign Monitor",
      with_steps: false,
      json_fields: {
        "send_reminders"      => "Yes",
        "flag_expired"        => "Yes",
        "reminder_after_days" => "3"
      },
      schedule: {
        frequency: "daily", run_at_time: "08:00", timezone: "Asia/Kolkata",
        enabled: true, notify_on_failure: true, notify_on_success: false,
        notify_on_partial_success: true, notify_caphive_on_error: true
      }
    },
    fields: [
      { name: "send_reminders",
        field_type: "Select", label: "Send e-sign reminders", meta_data: "Yes,No", position: 1,
        help_text: "When Yes, fires a resend for any document that has been in 'requested' e-sign " \
                   "status for longer than 'Reminder after (days)'. Uses the document's built-in " \
                   "resend eligibility check — ineligible documents are logged but not retried." },
      { name: "flag_expired",
        field_type: "Select", label: "Flag expired/voided documents", meta_data: "Yes,No", position: 2,
        help_text: "When Yes, surfaces documents with expired, cancelled, or voided e-sign status " \
                   "as warning issues in the report for manual ops review and re-initiation." },
      { name: "reminder_after_days",
        field_type: "NumberField", label: "Reminder after (days)", meta_data: "", position: 3,
        help_text: "Number of days a document may remain in 'requested' e-sign status before a " \
                   "resend is triggered. Measured against the document's updated_at timestamp. Default: 3." }
    ]
  },
  {
    tag: "DataQualityAgent",
    agent: {
      name:       "Data Quality",
      with_steps: false,
      json_fields: {
        "check_commitment_overflows" => "Yes",
        "check_missing_valuations"   => "Yes",
        "check_stale_fx_rates"       => "Yes",
        "send_report"                => "Yes",
        "stale_valuation_days"       => "90",
        "stale_fx_days"              => "30",
        "email"                      => ""
      },
      schedule: {
        frequency: "daily", run_at_time: "01:00", timezone: "Asia/Kolkata",
        enabled: true, notify_on_failure: true, notify_on_success: false,
        notify_on_partial_success: true, notify_caphive_on_error: true
      }
    },
    fields: [
      { name: "check_commitment_overflows",
        field_type: "Select", label: "Check commitment overflows", meta_data: "Yes,No", position: 1,
        help_text: "When Yes, flags any LP whose total called capital exceeds their committed amount. " \
                   "Overflow records appear as blocking issues requiring immediate ops correction." },
      { name: "check_missing_valuations",
        field_type: "Select", label: "Check missing/stale valuations", meta_data: "Yes,No", position: 2,
        help_text: "When Yes, identifies portfolio companies in the fund that have no valuation " \
                   "updated within 'Stale valuation (days)'. Stale valuations distort fund NAV reporting." },
      { name: "check_stale_fx_rates",
        field_type: "Select", label: "Check stale FX rates", meta_data: "Yes,No", position: 3,
        help_text: "When Yes, flags currencies used in the fund whose exchange rate has not been " \
                   "updated within 'Stale FX rate (days)'. Stale rates skew multi-currency valuations." },
      { name: "send_report",
        field_type: "Select", label: "Email quality report after each run", meta_data: "Yes,No", position: 4,
        help_text: "When Yes, emails the health score and per-check fix-it list to the addresses in " \
                   "'Report recipient email(s)'. If that field is blank, the report goes to all active " \
                   "employees of the entity." },
      { name: "stale_valuation_days",
        field_type: "NumberField", label: "Stale valuation threshold (days)", meta_data: "", position: 5,
        help_text: "Portfolio companies are flagged when their most recent valuation is older than this " \
                   "many days. Default: 90. Adjust to match your fund's regular valuation cadence." },
      { name: "stale_fx_days",
        field_type: "NumberField", label: "Stale FX rate threshold (days)", meta_data: "", position: 6,
        help_text: "Currency exchange rates are flagged when they have not been updated within this many " \
                   "days. Default: 30. Match to your FX data provider's update frequency." },
      { name: "email",
        field_type: "TextField", label: "Report recipient email(s)", meta_data: "", position: 7,
        help_text: "Comma-separated email addresses to receive the quality report. " \
                   "If blank, the report is sent to all active employees of the entity." }
    ]
  },
  {
    tag: "NoteSummarizerAgent",
    agent: {
      name:       "Note Summarizer",
      with_steps: false,
      json_fields: {
        "summary_period" => "Quarter",
        "tag_filter"     => "",
        "auto_tag_notes" => "Yes",
        "available_tags" => "call,meeting,kpi,board-meeting,fundraising,risk,hiring,operations"
      },
      schedule: {
        frequency: "monthly", run_on_day: 1, run_at_time: "06:00", timezone: "Asia/Kolkata",
        enabled: true, notify_on_failure: true, notify_on_success: false,
        notify_on_partial_success: true, notify_caphive_on_error: true
      }
    },
    fields: [
      { name: "summary_period",
        field_type: "Select", label: "Summary period", meta_data: "Month,Quarter", position: 1,
        help_text: "Lookback window for note collection. 'Month' summarises the previous complete " \
                   "calendar month; 'Quarter' summarises the previous complete calendar quarter. " \
                   "The period is computed relative to the date the agent runs." },
      { name: "tag_filter",
        field_type: "TextField", label: "Tag filter", meta_data: "", position: 2,
        help_text: "Comma-separated note tags to restrict which notes are collected, e.g. 'call,meeting'. " \
                   "Only notes matching at least one of these tags will be summarised. " \
                   "Leave blank to include all notes in the period (except prior summary notes)." },
      { name: "auto_tag_notes",
        field_type: "Select", label: "Auto-tag untagged notes", meta_data: "Yes,No", position: 3,
        help_text: "When Yes, any notes in the period that have no tags are sent to the LLM in one " \
                   "batch call for tag assignment before the summary runs. Tags are saved back to the " \
                   "Note records. Set to No to leave untagged notes as-is." },
      { name: "available_tags",
        field_type: "TextField", label: "Available tags (auto-tagging vocabulary)", meta_data: "", position: 4,
        help_text: "Comma-separated list of tags the LLM must choose from when auto-tagging notes, " \
                   "e.g. 'call,meeting,kpi,board-meeting'. The LLM is constrained to this list. " \
                   "Leave blank to let the LLM assign any concise, fund-relevant tags it deems appropriate." }
    ]
  },
  {
    tag: "DealManagementAgent",
    agent: {
      name:       "Deal Management",
      with_steps: false,
      json_fields: {
        "check_progress"         => "Yes",
        "stagnant_days"          => "7",
        "send_reminders"         => "Yes",
        "reminder_days"          => "7,3,1",
        "check_documents"        => "Yes",
        "required_docs"          => "",
        "extract_terms"          => "Yes",
        "term_extraction_prompt" => "",
        "summarize_notes"        => "Yes",
        "note_period"            => "Quarter",
        "score_investors"        => "No",
        "min_points_per_section" => "3",
        "notify_email"           => ""
      },
      schedule: {
        frequency: "weekly", run_on_day: 1, run_at_time: "07:00", timezone: "Asia/Kolkata",
        enabled: false, notify_on_failure: true, notify_on_success: false,
        notify_on_partial_success: false, notify_caphive_on_error: true
      }
    },
    fields: [
      { name: "check_progress",
        field_type: "Select", label: "Check deal progress", meta_data: "Yes,No", position: 1,
        help_text: "When Yes, flags investors with no update or activity completion within 'Stagnant days' " \
                   "as stagnant (blocking), and surfaces overdue DealActivity steps as blocking issues." },
      { name: "stagnant_days",
        field_type: "NumberField", label: "Stagnant threshold (days)", meta_data: "", position: 2,
        help_text: "A DealInvestor is flagged stagnant when both the investor record and all linked " \
                   "DealActivity rows have not been updated within this many days. Default: 7." },
      { name: "send_reminders",
        field_type: "Select", label: "Send activity reminders", meta_data: "Yes,No", position: 3,
        help_text: "When Yes, emails notify_email for incomplete DealActivities that are overdue or " \
                   "whose due date falls within the 'Reminder days' window. Deduplicates within a calendar " \
                   "day via last_reminded_on on the activity record." },
      { name: "reminder_days",
        field_type: "TextField", label: "Reminder days", meta_data: "", position: 4,
        help_text: "Comma-separated day offsets before a DealActivity's by_date that trigger a reminder, " \
                   "e.g. '7,3,1'. '0' means on the due date. Overdue activities (past due date) always " \
                   "fire regardless of this list." },
      { name: "check_documents",
        field_type: "Select", label: "Check document checklist", meta_data: "Yes,No", position: 5,
        help_text: "When Yes, verifies that each document name in 'Required documents' exists in the " \
                   "deal data room. Missing documents produce blocking issues; present ones produce " \
                   "success issues. Name matching is case-insensitive." },
      { name: "required_docs",
        field_type: "TextField", label: "Required documents", meta_data: "", position: 6,
        help_text: "Comma-separated document names that must be present in the deal data room before " \
                   "the deal advances, e.g. 'NDA, Term Sheet, Financial Model'. Blank = no check." },
      { name: "extract_terms",
        field_type: "Select", label: "Extract deal terms", meta_data: "Yes,No", position: 7,
        help_text: "When Yes, sends all documents in the deal data room to the LLM and stores the " \
                   "extracted JSON in the deal-level report. The extraction is cached — re-runs only " \
                   "when documents or the extraction prompt change." },
      { name: "term_extraction_prompt",
        field_type: "TextArea", label: "Term extraction prompt", meta_data: "", position: 8,
        help_text: "Custom instructions for term extraction, e.g. 'Extract: valuation, equity %, " \
                   "board seats'. The LLM returns a JSON object with your fields. " \
                   "Leave blank to use the default common deal terms (valuation, instrument, closing date, etc.)." },
      { name: "summarize_notes",
        field_type: "Select", label: "Summarize investor notes & docs", meta_data: "Yes,No", position: 9,
        help_text: "When Yes, the LLM produces a three-section summary (Key Themes, Action Items, " \
                   "Investor Engagement) for each active investor from their document folder and " \
                   "completed DealActivity attachments within the Note period. " \
                   "Investors with no documents are saved as 'skipped' at zero LLM cost." },
      { name: "note_period",
        field_type: "Select", label: "Note period", meta_data: "Month,Quarter", position: 10,
        help_text: "Lookback window for collecting investor documents and completed activity attachments. " \
                   "'Month' = previous calendar month; 'Quarter' = previous calendar quarter. " \
                   "Does not apply to deal-level term extraction, which always reads all data-room documents." },
      { name: "score_investors",
        field_type: "Select", label: "Score investors", meta_data: "Yes,No", position: 11,
        help_text: "When Yes, the LLM scores each active investor 0–100 using the uploaded skill file " \
                   "as the rubric. Requires a scoring_skill_file to be uploaded. Disabled by default — " \
                   "turn on only after uploading the skill file. Scores are written back to " \
                   "DealInvestor.ai_score and ai_grade." },
      { name: "scoring_skill_file",
        field_type: "File", label: "Scoring Skill File", meta_data: "", position: 12,
        help_text: "Markdown file defining the investor scoring rubric — dimensions, weights, and " \
                   "benchmarks. Upload a .md or .txt file. The LLM uses this as its scoring instructions. " \
                   "Same pattern as the PortfolioScoringAgent skill files." },
      { name: "min_points_per_section",
        field_type: "NumberField", label: "Min points per scoring section", meta_data: "", position: 13,
        help_text: "Minimum number of bullet points the LLM must produce per scoring dimension " \
                   "(positives, concerns) and per top-level list (Strengths, Risks, Recommendations). " \
                   "Increase for more granular output. Default: 3." },
      { name: "notify_email",
        field_type: "TextField", label: "Notify email", meta_data: "", position: 14,
        help_text: "Email address for all agent notifications: pipeline digest, activity reminders, " \
                   "and blocker alerts. All v1 notifications go to this single address. " \
                   "Leave blank to suppress all outbound email from this agent." }
    ]
  },
  {
    tag: "PortfolioScoringAgent",
    agent: {
      name:       "Portfolio Scoring Agent",
      with_steps: false,
      json_fields: {
        "min_points_per_section"   => "5",
        "kpi_frequency"            => "All",
        "docs_from_last_n_reports" => 3,
        "document_name_filter"     => ""
      }
      # No schedule — triggered on-demand or via the agent UI
    },
    fields: [
      # Skill files are uploaded via the agent edit page after seeding.
      # meta_data must follow "skill: true, sector: <SectorName>" — drives skill_for_sector matching.
      { name: "generic_skill_file",
        field_type: "File", label: "Generic Portfolio Skill", position: 1,
        meta_data: "skill: true, sector: General",
        help_text: "Markdown skill prompt file used as a fallback when no sector-specific skill " \
                   "is configured for a portfolio company's sector. Upload a .md or .txt file." },
      { name: "beauty_skincare_skill",
        field_type: "File", label: "Beauty & Skincare Skill", position: 2,
        meta_data: "skill: true, sector: Beauty & Skincare",
        help_text: "Sector-specific skill prompt for Beauty & Skincare portfolio companies. " \
                   "The agent matches this file when the portfolio company's sector field equals " \
                   "'Beauty & Skincare'. Upload a .md or .txt file." },
      { name: "min_points_per_section",
        field_type: "NumberField", label: "Min points per section", position: 3, meta_data: "",
        help_text: "Minimum number of bullet points the LLM must produce per scoring dimension " \
                   "(positives, concerns) and per list section (Strengths, Risks, Recommendations). " \
                   "Increase for more granular output. Default: 3." },
      { name: "kpi_frequency",
        field_type: "Select", label: "KPI frequency filter", position: 4,
        meta_data: "All,Month,Quarter,Half Year,Year,YTD",
        help_text: "Restricts which KPI report periods are sent to the LLM as context. " \
                   "'All' includes every period type. Select a specific period to focus the " \
                   "score on a single reporting cadence, e.g. 'Quarter' for quarterly KPIs only." },
      { name: "docs_from_last_n_reports",
        field_type: "NumberField", label: "Documents from last N KPI reports", position: 5, meta_data: "",
        help_text: "Number of the most recent Actual KPI report periods from which to pull attached " \
                   "documents as LLM context. Set to 1 to use only the latest report's attachments; " \
                   "increase to include historical documents. Default: 1." },
      { name: "document_name_filter",
        field_type: "TextField", label: "Document name filter", position: 6, meta_data: "",
        help_text: "Comma-separated document names (exact match) to include in the LLM context, " \
                   "e.g. 'Q3 Financials,Board Deck'. All other documents from the selected reports " \
                   "are ignored. Leave blank to send all documents from the selected KPI reports." }
    ]
  }
].freeze

namespace :support_agents do
  desc "Idempotently set up all SupportAgent FormTypes, custom fields, and agent records " \
       "for a given entity. Safe to re-run after adding new fields or agents. " \
       "Usage: rake 'support_agents:setup[ENTITY_ID]'"
  task :setup, [:entity_id] => :environment do |_, args|
    entity_id = args[:entity_id].to_i
    abort "Usage: rake 'support_agents:setup[ENTITY_ID]'" if entity_id.zero?

    entity = Entity.find_by(id: entity_id) || abort("Entity #{entity_id} not found")
    puts "=== Setting up SupportAgents for #{entity.name} (ID=#{entity_id}) ==="
    puts ""

    SUPPORT_AGENT_FORM_CONFIGS.each do |cfg|
      tag = cfg[:tag]

      # 1. Ensure FormType exists (or just extend if extend_only)
      ft = if cfg[:extend_only]
             FormType.find_by(entity_id: entity_id, name: "SupportAgent", tag: tag)
           else
             FormType.find_or_initialize_by(entity_id: entity_id, name: "SupportAgent", tag: tag)
           end

      unless ft
        puts "  [#{tag}] FormType not found — skipping field extensions"
        next
      end

      if ft.new_record?
        ft.save!
        puts "  [#{tag}] Created FormType (ID=#{ft.id})"
      else
        puts "  [#{tag}] FormType exists (ID=#{ft.id})"
      end

      # 2. Upsert each custom field — create if missing, update label/help_text if changed.
      #    field_type, meta_data, and position are only written on creation to avoid
      #    overwriting deliberate UI changes (e.g. re-ordered positions or option lists).
      cfg[:fields].each do |field_attrs|
        fcf = ft.form_custom_fields.find_or_initialize_by(name: field_attrs[:name])
        if fcf.new_record?
          fcf.assign_attributes(field_attrs)
          fcf.save!
          puts "    [fcf] '#{field_attrs[:name]}' (#{field_attrs[:field_type]}) — created"
        else
          # Only propagate human-readable metadata — never overwrite structural fields set via UI
          updatable = field_attrs.slice(:label, :help_text)
          changed   = updatable.any? { |k, v| fcf.send(k) != v }
          if changed
            fcf.update!(updatable)
            puts "    [fcf] '#{field_attrs[:name]}' — updated label/help_text"
          else
            puts "    [fcf] '#{field_attrs[:name]}' — up to date"
          end
        end
      end

      # 3. Create/update the SupportAgent record (only for non-extend_only configs)
      next unless cfg[:agent]

      agent_cfg = cfg[:agent]
      sa = SupportAgent.find_or_initialize_by(entity_id: entity_id, agent_type: tag)

      if sa.new_record?
        sa.assign_attributes(
          name:        agent_cfg[:name],
          form_type_id: ft.id,
          with_steps:  agent_cfg[:with_steps],
          enabled:     true,
          llm_model:   DEFAULT_LLM_MODEL,
          json_fields: agent_cfg[:json_fields] || {}
        )
        sa.save!
        puts "    [agent] Created #{tag} (ID=#{sa.id})"
      else
        # Merge new json_fields keys without overwriting existing values set via UI
        merged = agent_cfg[:json_fields].merge(sa.json_fields || {})
        sa.update!(json_fields: merged)
        puts "    [agent] Updated #{tag} (ID=#{sa.id}) — merged json_fields"
      end

      # 4. Ensure schedule if specified
      next unless agent_cfg[:schedule]

      sch = AgentSchedule.find_or_initialize_by(support_agent_id: sa.id)
      sch.assign_attributes(entity_id: entity_id, **agent_cfg[:schedule])
      sch.next_run_at ||= Time.zone.now.end_of_day
      sch.save!
      puts "    [schedule] #{agent_cfg[:schedule][:frequency]} at #{agent_cfg[:schedule][:run_at_time]} #{agent_cfg[:schedule][:timezone]}"
    end

    # Extend existing agents' json_fields with defaults for newly added fields
    {
      "KycOnboardingAgent"      => { "check_expiry" => "Yes", "expiry_warning_days" => "60,30,15" },
      "PortfolioCompanyAgent"   => { "send_kpi_reminder" => "Yes", "reminder_days" => "7,14,21" }
    }.each do |agent_type, defaults|
      sa = SupportAgent.find_by(entity_id: entity_id, agent_type: agent_type)
      next puts "  [#{agent_type}] Not found — skipping json_fields update" unless sa

      # Only add keys that aren't already set (don't overwrite UI-configured values)
      missing = defaults.reject { |k, _| sa.json_fields&.key?(k) }
      if missing.any?
        sa.update!(json_fields: (sa.json_fields || {}).merge(missing))
        puts "  [#{agent_type}] Added json_fields: #{missing.keys.join(', ')}"
      else
        puts "  [#{agent_type}] json_fields already up to date"
      end
    end

    # Seed KycDocExtractorAgent extraction_rules using the entity's actual KYC FormType IDs.
    # Only applied when extraction_rules is empty — existing UI-configured rules are never overwritten.
    sa = SupportAgent.find_by(entity_id: entity_id, agent_type: "KycDocExtractorAgent")
    if sa
      existing_rules = sa.json_fields&.dig("extraction_rules") || {}
      if existing_rules.empty?
        kyc_fts = FormType.where(entity_id: entity_id, name: %w[IndividualKyc NonIndividualKyc])
        if kyc_fts.any?
          rules = kyc_fts.each_with_object({}) do |ft, hash|
            # IndividualKyc/Default also extracts full_name; all other KYC types get PAN + address only.
            entry = KYC_EXTRACTOR_BASE_RULES.dup
            entry = entry + [KYC_EXTRACTOR_FULL_NAME_RULE] if ft.name == "IndividualKyc" && ft.tag == "Default"
            hash[ft.id.to_s] = entry
          end
          sa.update!(json_fields: sa.json_fields.merge("extraction_rules" => rules))
          puts "  [KycDocExtractorAgent] Seeded extraction_rules for #{kyc_fts.count} KYC FormTypes: " \
               "#{kyc_fts.map { |f| "#{f.name}/#{f.tag}(#{f.id})" }.join(', ')}"
        else
          puts "  [KycDocExtractorAgent] No IndividualKyc/NonIndividualKyc FormTypes found — extraction_rules not seeded"
        end
      else
        puts "  [KycDocExtractorAgent] extraction_rules already configured (#{existing_rules.size} form types) — skipped"
      end
    end

    puts ""
    puts "=== Done ==="
  end
  desc "Clone all SupportAgents from a source entity (default: 157) to a target entity. " \
       "Usage: rake 'support_agents:clone[TARGET_ENTITY_ID]'"
  task :clone, [:target_entity_id, :source_entity_id] => :environment do |_, args|
    source_entity_id = (args[:source_entity_id].presence || 157).to_i
    target_entity_id = args[:target_entity_id].to_i

    abort "Usage: rake 'support_agents:clone[TARGET_ENTITY_ID]'" if target_entity_id.zero?

    source_entity = Entity.find_by(id: source_entity_id) || abort("Source entity #{source_entity_id} not found")
    target_entity = Entity.find_by(id: target_entity_id) || abort("Target entity #{target_entity_id} not found")

    puts "=== Cloning SupportAgents ==="
    puts "Source: #{source_entity.name} (ID=#{source_entity_id})"
    puts "Target: #{target_entity.name} (ID=#{target_entity_id})"
    puts ""

    Chewy.strategy(:atomic) do
      # 1. Mirror all enabled support_agent bitflags
      clone_bitflags!(source_entity, target_entity)

      # 2. Clone each agent
      SupportAgent.where(entity_id: source_entity_id).order(:id).each do |source_agent|
        puts "--- #{source_agent.agent_type} (source ID=#{source_agent.id}) ---"

        target_form_type = clone_form_type!(source_agent, target_entity_id)
        target_agent     = clone_support_agent!(source_agent, target_entity_id, target_form_type)
        clone_documents!(source_agent, target_agent, target_entity_id)

        puts ""
      end
    end

    puts "=== Done ==="
  end

  # --- Helpers ---------------------------------------------------------------

  def clone_bitflags!(source_entity, target_entity)
    flag_names = %i[
      kyc_onboarding_agent portfolio_company_agent fund_stats_agent
      folio_assistant portfolio_assistant fund_assistant
      report_analysis_agent portfolio_scoring_agent deal_management_agent
    ]

    changed = false
    flag_names.each do |flag|
      next unless source_entity.support_agents.set?(flag)
      next if target_entity.support_agents.set?(flag)

      target_entity.support_agents.set(flag)
      puts "  [flag] Enabled :#{flag}"
      changed = true
    end

    if changed
      target_entity.save!
      puts "  [flag] Saved entity flags"
    else
      puts "  [flag] All flags already set — skipped"
    end
  end

  # Clones the FormType (and all its FormCustomFields) from source_agent to the target entity.
  # Returns the target FormType, or nil if the source agent has no form type.
  def clone_form_type!(source_agent, target_entity_id)
    source_ft = source_agent.form_type
    return nil unless source_ft

    # FormType name must be a constantizable model name (e.g. "SupportAgent"), tag differentiates
    target_ft = FormType.find_or_initialize_by(
      entity_id: target_entity_id,
      name:      source_ft.name,
      tag:       source_ft.tag
    )

    if target_ft.new_record?
      target_ft.save!
      puts "  [form_type] Created FormType '#{source_ft.name}/#{source_ft.tag}' (ID=#{target_ft.id})"
    else
      puts "  [form_type] Exists FormType '#{source_ft.name}/#{source_ft.tag}' (ID=#{target_ft.id})"
    end

    # Clone custom fields (non-File types — File fields are cloned via documents)
    source_agent.form_custom_fields.each do |source_fcf|
      clone_form_custom_field!(source_fcf, target_ft)
    end

    target_ft
  end

  CLONED_FCF_COLUMNS = %w[
    name field_type label required meta_data has_attachment position
    help_text read_only show_user_ids step condition_on condition_criteria
    condition_params condition_state internal js_events reg_env validation_rules
  ].freeze

  def clone_form_custom_field!(source_fcf, target_ft)
    target_fcf = FormCustomField.find_or_initialize_by(
      form_type_id: target_ft.id,
      name:         source_fcf.name
    )

    if target_fcf.new_record?
      target_fcf.assign_attributes(source_fcf.slice(*CLONED_FCF_COLUMNS))
      target_fcf.save!
      puts "  [fcf] Created '#{source_fcf.human_label}' (#{source_fcf.field_type})"
    else
      puts "  [fcf] Exists '#{source_fcf.human_label}' (#{source_fcf.field_type})"
    end

    target_fcf
  end

  # Clones the SupportAgent itself (configuration, model, json_fields).
  # Uniqueness key: (entity_id, agent_type, form_type_id).
  def clone_support_agent!(source_agent, target_entity_id, target_form_type)
    target_agent = SupportAgent.find_or_initialize_by(
      entity_id:    target_entity_id,
      agent_type:   source_agent.agent_type,
      form_type_id: target_form_type&.id
    )

    if target_agent.new_record?
      target_agent.assign_attributes(
        name:        source_agent.name,
        description: source_agent.description,
        enabled:     source_agent.enabled,
        llm_model:   source_agent.llm_model,
        with_steps:  source_agent.with_steps,
        json_fields: source_agent.json_fields.presence || {}
      )
      target_agent.save!
      puts "  [agent] Created #{source_agent.agent_type} (ID=#{target_agent.id})"
    else
      puts "  [agent] Exists #{source_agent.agent_type} (ID=#{target_agent.id})"
    end

    target_agent
  end

  # Copies all documents attached to File-type custom fields from source_agent to target_agent.
  def clone_documents!(source_agent, target_agent, target_entity_id)
    file_fcfs = source_agent.form_custom_fields.select { |f| f.field_type == "File" }
    return if file_fcfs.empty?

    user = User.where(entity_id: target_entity_id).first

    file_fcfs.each do |fcf|
      source_doc = source_agent.documents.find_by(name: fcf.human_label)
      unless source_doc&.file&.present?
        puts "  [doc] '#{fcf.human_label}' — no source file, skipped"
        next
      end

      # Skip if target already has this document
      if target_agent.documents.find_by(name: fcf.human_label)
        puts "  [doc] '#{fcf.human_label}' — already exists, skipped"
        next
      end

      begin
        file_content = source_doc.file.open(&:read)
        original_name = source_doc.file.original_filename.to_s

        # Normalise to text/plain for .md files (text/markdown is not in ALLOWED_TYPES)
        content_type = original_name.end_with?(".md") ? "text/plain" : (source_doc.file.metadata["mime_type"] || "text/plain")
        safe_name    = original_name.sub(/\.md$/, ".txt")

        file_io = StringIO.new(file_content)
        file_io.define_singleton_method(:original_filename) { safe_name }
        file_io.define_singleton_method(:content_type)      { content_type }

        target_doc = Document.new(
          owner:     target_agent,
          name:      fcf.human_label,
          entity_id: target_entity_id,
          user_id:   user&.id,
          owner_tag: source_doc.owner_tag
        )
        target_doc.file = file_io
        target_doc.save!
        puts "  [doc] Copied '#{fcf.human_label}' → Document ID=#{target_doc.id}"
      rescue StandardError => e
        puts "  [doc] ERROR copying '#{fcf.human_label}': #{e.message}"
      end
    end
  end
end
