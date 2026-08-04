# Service class that idempotently provisions all SupportAgent FormTypes, custom fields,
# and agent records for a given entity. Extracted from lib/tasks/support_agents.rake so
# the same logic can be called from seeds, tests, or other service objects.
#
# Usage:
#   SupportAgentsSetupService.new(entity_id).call
#   SupportAgentsSetupService.new(entity_id, output: Rails.logger).call
class SupportAgentsSetupService
  DEFAULT_LLM_MODEL = "gemini-3-flash-preview"

  # Extraction rule templates for KycDocExtractorAgent.
  # Applied dynamically at setup time, keyed by the entity's actual KYC FormType IDs.
  KYC_EXTRACTOR_BASE_RULES = [
    { "doc_label" => "Upload Tax ID",        "prompt" => "Extract the PAN number from this document. Return only the 10-character alphanumeric PAN (e.g. ABCDE1234F). No explanation.", "target_field" => "PAN" },
    { "doc_label" => "Upload Address Proof", "prompt" => "Extract the full permanent address from this document. Return only the address as plain text, no labels or explanation.",    "target_field" => "address" }
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
      extend_only: true, # FormType already exists; only add/update fields
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
          help_text: "When Yes, sends a consolidated reminder email to the portfolio company listing " \
                     "missing items (KPIs, documents, valuations) on each run inside the active checking " \
                     "window. At most one reminder is sent per day." }
        # reminder_days was removed when reminders moved to the active-window model —
        # cadence now follows the agent's run schedule, not a fixed day list.
      ]
    },

    # ── New agent FormTypes (created when missing) ─────────────────────────────
    {
      tag: "KycDocExtractorAgent",
      category: "Onboarding",
      agent: {
        name:       "KYC Doc Extractor",
        with_steps: false,
        json_fields: {
          "overwrite_mode"   => "blank_only",
          "extraction_rules" => {} # populated dynamically from the entity's KYC FormTypes
        }
        # No schedule — triggered on-demand during KYC document upload
      },
      # All runtime config is managed via the dedicated _kyc_doc_extractor_config partial;
      # no FormCustomField records needed.
      fields: []
    },
    {
      tag: "DistributionReadinessAgent",
      category: "Finance",
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
      category: "Ops",
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
      category: "Ops",
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
      category: "Ops",
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
      category: "Portfolio",
      agent: {
        name:       "Deal Management",
        with_steps: false,
        json_fields: {
          "check_progress"         => "Yes",
          "stagnant_days"          => "14",
          "check_documents"        => "Yes",
          "required_docs"          => "NDA, Term Sheet, Pitch Deck",
          "extract_terms"          => "Yes",
          "term_extraction_prompt" => "",
          "summarize_notes"        => "Yes",
          "note_period"            => "Quarter",
          "score_investors"        => "Yes",
          "min_points_per_section" => "3",
          "notify_email"           => "",
          # enabled? fails closed — these were previously unseeded, leaving the
          # weekly summary email and AI insight permanently (and silently) off
          "weekly_summary"         => "Yes",
          "enable_ai_insight"      => "Yes"
        },
        # Bundled seed file for the scoring rubric — uploaded automatically on first setup.
        # Path is relative to Rails.root. Skipped silently if the file is absent.
        skill_files: {
          "scoring_skill_file" => "public/sample_uploads/investor_scoring_rubric.txt"
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
                     "DealActivity rows have not been updated within this many days. Default: 14." },
        { name: "check_documents",
          field_type: "Select", label: "Check document checklist", meta_data: "Yes,No", position: 3,
          help_text: "When Yes, verifies that each document name in 'Required documents' exists in the " \
                     "deal data room. Missing documents produce blocking issues; present ones produce " \
                     "success issues. Name matching is case-insensitive." },
        { name: "required_docs",
          field_type: "TextField", label: "Required documents", meta_data: "", position: 4,
          help_text: "Comma-separated document names that must be present in the deal data room, " \
                     "e.g. 'NDA, Term Sheet, Pitch Deck, Financial Model'. Blank = no check." },
        { name: "extract_terms",
          field_type: "Select", label: "Extract deal terms", meta_data: "Yes,No", position: 5,
          help_text: "When Yes, sends all documents in the deal data room to the LLM and stores the " \
                     "extracted JSON in the deal-level report. The extraction is cached — re-runs only " \
                     "when documents or the extraction prompt change." },
        { name: "term_extraction_prompt",
          field_type: "TextArea", label: "Term extraction prompt", meta_data: "", position: 6,
          help_text: "Custom instructions for term extraction, e.g. 'Extract: valuation, equity %, " \
                     "board seats'. The LLM returns a JSON object with your fields. " \
                     "Leave blank to use the default common deal terms (valuation, instrument, closing date, etc.)." },
        { name: "summarize_notes",
          field_type: "Select", label: "Summarize investor notes & docs", meta_data: "Yes,No", position: 7,
          help_text: "When Yes, the LLM produces a three-section summary (Key Themes, Action Items, " \
                     "Investor Engagement) for each active investor from their document folder and " \
                     "completed DealActivity attachments within the Note period. " \
                     "Investors with no documents are saved as 'skipped' at zero LLM cost." },
        { name: "note_period",
          field_type: "Select", label: "Note period", meta_data: "Month,Quarter", position: 8,
          help_text: "Lookback window for collecting investor documents and completed activity attachments. " \
                     "'Month' = previous calendar month; 'Quarter' = previous calendar quarter. " \
                     "Does not apply to deal-level term extraction, which always reads all data-room documents." },
        { name: "score_investors",
          field_type: "Select", label: "Score investors", meta_data: "Yes,No", position: 9,
          help_text: "When Yes, the LLM scores each active investor 0–100 using the Scoring Skill File " \
                     "as the rubric. A default rubric is seeded automatically by the setup task. " \
                     "Scores are written to the investor report; dimensions shown 0–20 each." },
        { name: "scoring_skill_file",
          field_type: "File", label: "Scoring Skill File", meta_data: "", position: 10,
          help_text: "Text or Markdown file defining the investor scoring rubric — 5 dimensions scored " \
                     "0–20 each (total 100). A default rubric is uploaded automatically by the setup task. " \
                     "Replace it with a custom file to tune scoring to your fund's criteria." },
        { name: "min_points_per_section",
          field_type: "NumberField", label: "Min bullet points per section", meta_data: "", position: 11,
          help_text: "Minimum bullet points the LLM must produce per scoring dimension rationale. " \
                     "Increase for more granular output. Default: 3." },
        { name: "notify_email",
          field_type: "TextField", label: "Notify email", meta_data: "", position: 12,
          help_text: "Email address for the pipeline digest sent after every agent run. " \
                     "Includes overdue activities, document gaps, investor scores, and extracted terms. " \
                     "Leave blank to suppress all outbound email from this agent." }
      ]
    },
    {
      tag: "PortfolioScoringAgent",
      category: "Portfolio",
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
    },

    # ── PresentationAnalystAgent ─────────────────────────────────────────────────
    {
      tag: "PresentationAnalystAgent",
      category: "Portfolio",
      agent: {
        name:       "Investor Presentation Analyst",
        with_steps: true, # shows the 7-step progress panel in the agent UI
        json_fields: {
          "presentation_doc_names" => "Investor Update, Board Deck, Management Presentation, Quarterly Update, Investor Presentation",
          "max_periods"            => "8",
          "kpi_tag_list"           => "Actual",
          "comparison_strategy"    => "all_periods",
          "llm_model"              => "gemini-3-flash-preview",
          "chat_config"            => { "enabled" => "true" }
        },
        schedule: {
          frequency: "monthly", run_on_day: 1, run_at_time: "06:00", timezone: "Asia/Kolkata",
          enabled: false,
          notify_on_failure:         true,
          notify_on_success:         false,
          notify_on_partial_success: true,
          notify_caphive_on_error:   true
        }
      },
      fields: [
        { name: "presentation_doc_names",
          field_type: "TextField", label: "Presentation document names", meta_data: "", position: 1,
          help_text: "Comma-separated substrings matched (case-insensitively) against document names " \
                     "on each KPI report. Documents whose names contain any of these strings are treated " \
                     "as investor presentations. Default: 'Investor Update, Board Deck, Management " \
                     "Presentation, Quarterly Update, Investor Presentation'." },
        { name: "max_periods",
          field_type: "NumberField", label: "Max periods to analyze", meta_data: "", position: 2,
          help_text: "Maximum number of the most recent KPI report periods to include. Older periods " \
                     "beyond this count are skipped. Increase for a longer history; reduce to lower LLM " \
                     "cost and latency. Default: 8." },
        { name: "kpi_tag_list",
          field_type: "Select", label: "KPI report tag", meta_data: "Actual,Budget,IC", position: 3,
          help_text: "Restricts which KpiReports are scanned for presentation documents. 'Actual' " \
                     "(default) covers real reported figures. 'Budget' and 'IC' cover projections and " \
                     "investment committee submissions respectively." },
        { name: "comparison_strategy",
          field_type: "Select", label: "Comparison strategy", meta_data: "all_periods,sliding_window", position: 4,
          help_text: "'all_periods' sends all extracted period records in one LLM call — more accurate " \
                     "because the model sees the full temporal arc. 'sliding_window' makes one call per " \
                     "adjacent pair (N-1 → N) — cheaper when there are many periods. Default: all_periods." },
        { name: "llm_model",
          field_type: "TextField", label: "LLM model", meta_data: "", position: 5,
          help_text: "LLM model name used for all extraction, comparison, and question-generation calls. " \
                     "Must support a large context window (≥500K tokens) to process full presentations " \
                     "without truncation. Default: gemini-3-flash-preview (1M token context)." }
      ]
    },

    # ── RtaReconciliationAgent ────────────────────────────────────────────────
    {
      tag: "RtaReconciliationAgent",
      agent: {
        name:       "RTA Reconciliation",
        with_steps: true,
        json_fields: {
          "tolerance_units"        => "0.01",
          "tolerance_pct"          => "0",
          "check_pending_requests" => "Yes",
          "send_report"            => "Yes",
          "notify_email"           => ""
          # No default schedule — runs on-demand at statement upload time
        }
      },
      # No File field here for the statement itself — it's uploaded per-run through the
      # dedicated run modal (rta_run_modal.html.erb), not through the agent's config form.
      fields: [
        { name: "tolerance_units",
          field_type: "NumberField", label: "Tolerance (units)", meta_data: "", position: 1,
          help_text: "Maximum absolute unit difference per folio or summary that is still treated as " \
                     "a match. Accommodates minor rounding in RTA PDFs. Default: 0.01." },
        { name: "tolerance_pct",
          field_type: "NumberField", label: "Tolerance (%)", meta_data: "", position: 2,
          help_text: "Maximum percentage difference. A break is flagged only when both absolute and " \
                     "percentage differences exceed their respective tolerances. Set to 0 to use " \
                     "absolute tolerance only (default)." },
        { name: "check_pending_requests",
          field_type: "Select", label: "Flag pending requests", meta_data: "Yes,No", position: 3,
          help_text: "When Yes, folios where the RTA statement shows pending transactions (e.g. " \
                     "Pending TXN, Outstanding Requests) are flagged as warnings. These are not " \
                     "breaks but signal in-flight transactions that may cause a discrepancy next period." },
        { name: "send_report",
          field_type: "Select", label: "Email report after run", meta_data: "Yes,No", position: 4,
          help_text: "When Yes, emails the reconciliation summary — scheme match status, break count, " \
                     "and folio-level detail — to the address in 'Notify email' after each run." },
        { name: "notify_email",
          field_type: "TextField", label: "Notify email", meta_data: "", position: 5,
          help_text: "Email address to receive the reconciliation report. Required when 'Email report " \
                     "after run' is Yes. Leave blank to skip email delivery." },
        { name: "statement_date",
          field_type: "DateField", label: "Statement date override", meta_data: "", position: 6,
          help_text: "Optional. When set, overrides the statement period-end date extracted from the " \
                     "PDF. Use when the RTA's date format is non-standard and extraction is incorrect." }
      ]
    },

    # ── Additional agents (category provisioning only) ───────────────────────────
    {
      tag: "FundStatsAgent",
      category: "Ops",
      agent: { name: "Fund Stats", with_steps: false, json_fields: {} },
      fields: []
    },
    {
      tag: "PortfolioReportAgent",
      category: "Portfolio",
      agent: { name: "Portfolio Report", with_steps: false, json_fields: {} },
      fields: []
    },
    {
      tag: "CallNoticeAgent",
      category: "Ops",
      agent: { name: "Call Notice", with_steps: false, json_fields: {} },
      fields: []
    },
    {
      tag: "CashFlowAssistantAgent",
      category: "Ops",
      agent: { name: "Cash Flow Assistant", with_steps: false, json_fields: {} },
      fields: []
    },
    {
      tag: "DealsReportAgent",
      category: "Deal",
      agent: { name: "Deals Report", with_steps: false, json_fields: {} },
      fields: []
    }
  ].freeze

  # agent_type strings whose support_agents flag name doesn't follow the simple underscore convention.
  AGENT_TYPE_TO_FLAG = {
    "NoteSummarizerAgent"     => :note_summarization_agent,
    "LpAssistantAgent"        => :folio_assistant,
    "PortfolioAssistantAgent" => :portfolio_assistant,
    "CashFlowAssistantAgent"  => :cash_flow_assistant_agent, # explicit for clarity
  }.freeze

  # @param entity_id [Integer]
  # @param output [IO, Logger] where log lines are written (defaults to $stdout)
  def initialize(entity_id, output: $stdout)
    @entity_id = entity_id
    @output    = output
  end

  # Idempotently provisions FormTypes, custom fields, agent records, schedules,
  # and seed documents for the entity. Safe to re-run after adding new agents or fields.
  def call
    @entity = Entity.find_by(id: @entity_id) || raise(ActiveRecord::RecordNotFound, "Entity #{@entity_id} not found")

    log "=== Setting up SupportAgents for #{@entity.name} (ID=#{@entity_id}) ==="
    log ""

    SUPPORT_AGENT_FORM_CONFIGS.each { |cfg| setup_config(cfg) }

    cleanup_deprecated_deal_management_fields
    backfill_extend_only_json_fields
    seed_kyc_extractor_rules
    seed_skill_files

    log ""
    log "=== Done ==="
  end

  # Resolves the support_agents bitflag symbol for a given agent_type string.
  # Used by SupportAgent#entity_flag_enabled? to check the entity's bitflag.
  def self.flag_for(agent_type)
    AGENT_TYPE_TO_FLAG.fetch(agent_type) { agent_type.underscore.to_sym }
  end

  # Returns the template definitions of skill File fields for the given agent type —
  # the source of truth for which fields MUST be tagged "skill: true, sector: …".
  # Used by config health checks (e.g. PortfolioScoringAgent.config_issues) to detect
  # instances whose live fields drifted from the template (blank meta_data etc.).
  # Agent types without skill fields in their template return [] — so checks driven
  # by this method are automatically a no-op for every other agent.
  #
  # @param agent_type [String] e.g. "PortfolioScoringAgent"
  # @return [Array<Hash>] template field attrs whose meta_data marks them as skills
  def self.skill_field_templates(agent_type)
    cfg = SUPPORT_AGENT_FORM_CONFIGS.find { |c| c[:tag] == agent_type }
    return [] unless cfg

    (cfg[:fields] || []).select { |f| f[:field_type] == "File" && f[:meta_data].to_s.match?(/skill/i) }
  end

  private

  def log(msg)
    if @output.respond_to?(:info)
      @output.info(msg)
    else
      @output.puts(msg)
    end
  end

  # ── Per-config setup ────────────────────────────────────────────────────────

  def setup_config(cfg)
    tag = cfg[:tag]
    ft  = find_or_create_form_type(cfg)
    return unless ft

    upsert_custom_fields(ft, cfg[:fields])
    setup_agent(ft, cfg) if cfg[:agent]
  end

  def find_or_create_form_type(cfg)
    tag = cfg[:tag]

    ft = if cfg[:extend_only]
           FormType.find_by(entity_id: @entity_id, name: "SupportAgent", tag: tag)
         else
           FormType.find_or_initialize_by(entity_id: @entity_id, name: "SupportAgent", tag: tag)
         end

    unless ft
      log "  [#{tag}] FormType not found — skipping field extensions"
      return nil
    end

    if ft.new_record?
      ft.save!
      log "  [#{tag}] Created FormType (ID=#{ft.id})"
    else
      log "  [#{tag}] FormType exists (ID=#{ft.id})"
    end

    ft
  end

  def upsert_custom_fields(ft, fields)
    fields.each do |field_attrs|
      fcf = ft.form_custom_fields.find_or_initialize_by(name: field_attrs[:name])
      if fcf.new_record?
        fcf.assign_attributes(field_attrs)
        fcf.save!
        log "    [fcf] '#{field_attrs[:name]}' (#{field_attrs[:field_type]}) — created"
      else
        # Only propagate human-readable metadata — never overwrite structural fields set via UI
        updatable = field_attrs.slice(:label, :help_text)

        # Exception: skill-tagged File fields (meta_data "skill: true, sector: …") are
        # non-functional without their meta_data — skill_for_sector can never match them.
        # Backfill it ONLY when the template tags the field as a skill AND the live value
        # is blank (a blank skill tag is always drift, never a deliberate UI setting).
        # Fields whose template meta_data is not skill-tagged — i.e. every other agent —
        # are never touched.
        if field_attrs[:field_type] == "File" && field_attrs[:meta_data].to_s.match?(/skill/i) && fcf.meta_data.blank?
          updatable[:meta_data] = field_attrs[:meta_data]
        end

        changed = updatable.any? { |k, v| fcf.send(k) != v }
        if changed
          fcf.update!(updatable)
          log "    [fcf] '#{field_attrs[:name]}' — updated #{updatable.keys.join('/')}"
        else
          log "    [fcf] '#{field_attrs[:name]}' — up to date"
        end
      end
    end
  end

  def setup_agent(ft, cfg)
    tag       = cfg[:tag]
    agent_cfg = cfg[:agent]

    sa = SupportAgent.find_or_initialize_by(entity_id: @entity_id, agent_type: tag)

    if sa.new_record?
      sa.assign_attributes(
        name:         agent_cfg[:name],
        form_type_id: ft.id,
        with_steps:   agent_cfg[:with_steps],
        enabled:      true,
        llm_model:    DEFAULT_LLM_MODEL,
        category:     cfg[:category],
        json_fields:  agent_cfg[:json_fields] || {}
      )
      sa.save!
      log "    [agent] Created #{tag} (ID=#{sa.id})"
    else
      updates = {}
      # Merge new json_fields keys without overwriting existing values set via UI
      merged = agent_cfg[:json_fields].merge(sa.json_fields || {})
      updates[:json_fields] = merged
      # Backfill category on existing records that lack one
      updates[:category] = cfg[:category] if sa.category.blank? && cfg[:category]
      sa.update!(updates)
      log "    [agent] Updated #{tag} (ID=#{sa.id}) — merged json_fields#{', set category' if updates.key?(:category)}"
    end

    setup_schedule(sa, agent_cfg[:schedule]) if agent_cfg[:schedule]
  end

  def setup_schedule(sa, schedule_cfg)
    sch = AgentSchedule.find_or_initialize_by(support_agent_id: sa.id)
    sch.assign_attributes(entity_id: @entity_id, **schedule_cfg)
    sch.next_run_at ||= Time.zone.now.end_of_day
    sch.save!
    log "    [schedule] #{schedule_cfg[:frequency]} at #{schedule_cfg[:run_at_time]} #{schedule_cfg[:timezone]}"
  end

  # ── Post-setup passes ────────────────────────────────────────────────────────

  # Remove deprecated json_fields keys from DealManagementAgent.
  # (send_reminders and reminder_days were removed when per-activity emails
  # were consolidated into the digest.)
  def cleanup_deprecated_deal_management_fields
    dma = SupportAgent.find_by(entity_id: @entity_id, agent_type: "DealManagementAgent")
    return unless dma

    stale_keys = %w[send_reminders reminder_days]
    present    = stale_keys.select { |k| dma.json_fields&.key?(k) }
    if present.any?
      dma.update!(json_fields: dma.json_fields.except(*present))
      log "  [DealManagementAgent] Removed deprecated json_fields: #{present.join(', ')}"
    else
      log "  [DealManagementAgent] No deprecated json_fields to remove"
    end
  end

  # Extend existing agents' json_fields with defaults for newly added fields.
  # Only adds keys that are missing — never overwrites UI-configured values.
  def backfill_extend_only_json_fields
    {
      # validate_fields/validate_documents: enabled? fails closed, so without a
      # seeded value the core KYC checks silently skip. send_reminder/trigger_aml
      # are deliberately NOT seeded (outbound email / AML screening should be an
      # explicit opt-in) — config_issues surfaces them instead.
      "KycOnboardingAgent"    => { "check_expiry" => "Yes", "expiry_warning_days" => "60,30,15",
                                   "validate_fields" => "Yes", "validate_documents" => "Yes" },
      # reminder_days is gone — reminders follow the active-window model now
      "PortfolioCompanyAgent" => { "send_kpi_reminder" => "Yes" }
    }.each do |agent_type, defaults|
      sa = SupportAgent.find_by(entity_id: @entity_id, agent_type: agent_type)
      next log "  [#{agent_type}] Not found — skipping json_fields update" unless sa

      missing = defaults.reject { |k, _| sa.json_fields&.key?(k) }
      if missing.any?
        sa.update!(json_fields: (sa.json_fields || {}).merge(missing))
        log "  [#{agent_type}] Added json_fields: #{missing.keys.join(', ')}"
      else
        log "  [#{agent_type}] json_fields already up to date"
      end
    end
  end

  # Seed KycDocExtractorAgent extraction_rules using the entity's actual KYC FormType IDs.
  # Only applied when extraction_rules is empty — existing UI-configured rules are never overwritten.
  def seed_kyc_extractor_rules
    sa = SupportAgent.find_by(entity_id: @entity_id, agent_type: "KycDocExtractorAgent")
    return unless sa

    existing_rules = sa.json_fields&.dig("extraction_rules") || {}
    if existing_rules.present?
      log "  [KycDocExtractorAgent] extraction_rules already configured (#{existing_rules.size} form types) — skipped"
      return
    end

    kyc_fts = FormType.where(entity_id: @entity_id, name: %w[IndividualKyc NonIndividualKyc])
    if kyc_fts.none?
      log "  [KycDocExtractorAgent] No IndividualKyc/NonIndividualKyc FormTypes found — extraction_rules not seeded"
      return
    end

    rules = kyc_fts.each_with_object({}) do |ft, hash|
      entry = KYC_EXTRACTOR_BASE_RULES.dup
      entry = entry + [KYC_EXTRACTOR_FULL_NAME_RULE] if ft.name == "IndividualKyc" && ft.tag == "Default"
      hash[ft.id.to_s] = entry
    end
    sa.update!(json_fields: sa.json_fields.merge("extraction_rules" => rules))
    log "  [KycDocExtractorAgent] Seeded extraction_rules for #{kyc_fts.count} KYC FormTypes: " \
        "#{kyc_fts.map { |f| "#{f.name}/#{f.tag}(#{f.id})" }.join(', ')}"
  end

  # Upload bundled skill files declared in each agent's skill_files hash.
  # Idempotent: skips if the document already exists on the agent.
  def seed_skill_files
    log ""
    log "=== Seeding skill files ==="
    user = User.where(entity_id: @entity_id).first

    SUPPORT_AGENT_FORM_CONFIGS.each do |cfg|
      next unless cfg.dig(:agent, :skill_files)&.any?

      sa = SupportAgent.find_by(entity_id: @entity_id, agent_type: cfg[:tag])
      next log "  [#{cfg[:tag]}] agent not found — skipping skill files" unless sa

      cfg[:agent][:skill_files].each do |field_name, relative_path|
        upload_skill_file(sa, field_name, relative_path, user)
      end
    end
  end

  def upload_skill_file(sa, field_name, relative_path, user)
    fcf = sa.form_custom_fields.find { |f| f.name == field_name && f.field_type == "File" }
    unless fcf
      log "  [#{sa.agent_type}] FormCustomField '#{field_name}' not found — skipping"
      return
    end

    doc_name = fcf.human_label
    if sa.documents.find_by(name: doc_name)
      log "  [#{sa.agent_type}] '#{doc_name}' already uploaded — skipped"
      return
    end

    file_path = Rails.root.join(relative_path)
    unless File.exist?(file_path)
      log "  [#{sa.agent_type}] seed file not found at #{file_path} — skipped"
      return
    end

    begin
      doc = Document.new(
        owner:      sa,
        name:       doc_name,
        entity_id:  @entity_id,
        user_id:    user&.id,
        send_email: false,
        folder:     sa.document_folder
      )
      doc.file = File.open(file_path)
      doc.save!
      log "  [#{sa.agent_type}] Uploaded '#{doc_name}' → Document##{doc.id}"
    rescue StandardError => e
      log "  [#{sa.agent_type}] ERROR uploading '#{doc_name}': #{e.message}"
    end
  end
end
