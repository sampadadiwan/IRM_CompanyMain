# Support Agent setup for entity 157 (Demo Fund)
#
# Run with:
#   bundle exec rails runner db/seeds/support_agent_setup_157.rb
#
# Idempotent — safe to run multiple times.

ENTITY_ID = 157

# ---------------------------------------------------------------------------
# 1. Extend existing FormTypes with new config fields
# ---------------------------------------------------------------------------

# KycOnboardingAgent (FormType 90) — add expiry fields
ft_kyc = FormType.find(90)
[
  { name: "check_expiry",        field_type: "Select",      label: "Check expiry status",    meta_data: "Yes,No", position: 8 },
  { name: "expiry_warning_days", field_type: "TextField",   label: "Expiry warning days",    meta_data: "",       position: 9,
    help_text: "Comma-separated day thresholds before expiry to warn, e.g. 60,30,15" }
].each do |attrs|
  next if ft_kyc.form_custom_fields.exists?(name: attrs[:name])
  ft_kyc.form_custom_fields.create!(attrs)
  puts "  Added field '#{attrs[:name]}' to FormType #{ft_kyc.id} (#{ft_kyc.tag})"
end

# PortfolioCompanyAgent (FormType 91) — add KPI reminder fields
ft_portco = FormType.find(91)
[
  { name: "send_kpi_reminder", field_type: "Select",    label: "Send KPI reminder",   meta_data: "Yes,No", position: 7 },
  { name: "reminder_days",     field_type: "TextField", label: "Reminder days",       meta_data: "",       position: 8,
    help_text: "Comma-separated day offsets from period start to send reminders, e.g. 7,14,21" }
].each do |attrs|
  next if ft_portco.form_custom_fields.exists?(name: attrs[:name])
  ft_portco.form_custom_fields.create!(attrs)
  puts "  Added field '#{attrs[:name]}' to FormType #{ft_portco.id} (#{ft_portco.tag})"
end

# ---------------------------------------------------------------------------
# 2. Create new FormTypes + FormCustomFields for the three new agent classes
# ---------------------------------------------------------------------------

new_form_types = [
  {
    name: "SupportAgent", tag: "DistributionReadinessAgent",
    fields: [
      { name: "check_kyc",           field_type: "Select",      label: "Check investor KYC",         meta_data: "Yes,No", position: 1 },
      { name: "check_net_payable",   field_type: "Select",      label: "Check net payable computed", meta_data: "Yes,No", position: 2 },
      { name: "check_docs_generated",field_type: "Select",      label: "Check notices generated",    meta_data: "Yes,No", position: 3 },
      { name: "check_docs_approved", field_type: "Select",      label: "Check notices approved",     meta_data: "Yes,No", position: 4 },
      { name: "check_bank_details",  field_type: "Select",      label: "Check bank details",         meta_data: "Yes,No", position: 5 }
    ]
  },
  {
    name: "SupportAgent", tag: "EsignMonitorAgent",
    fields: [
      { name: "send_reminders",       field_type: "Select",      label: "Send e-sign reminders",     meta_data: "Yes,No", position: 1 },
      { name: "flag_expired",         field_type: "Select",      label: "Flag expired documents",    meta_data: "Yes,No", position: 2 },
      { name: "reminder_after_days",  field_type: "NumberField", label: "Reminder after (days)",     meta_data: "",       position: 3,
        help_text: "Days a document stays in 'requested' before a resend is triggered (default 3)" }
    ]
  },
  {
    name: "SupportAgent", tag: "DataQualityAgent",
    fields: [
      { name: "check_commitment_overflows", field_type: "Select",      label: "Check commitment overflows", meta_data: "Yes,No", position: 1 },
      { name: "check_missing_valuations",   field_type: "Select",      label: "Check missing valuations",   meta_data: "Yes,No", position: 2 },
      { name: "check_stale_fx_rates",       field_type: "Select",      label: "Check stale FX rates",       meta_data: "Yes,No", position: 3 },
      { name: "send_report",                field_type: "Select",      label: "Send quality report email",  meta_data: "Yes,No", position: 4 },
      { name: "stale_valuation_days",       field_type: "NumberField", label: "Stale valuation (days)",     meta_data: "",       position: 5,
        help_text: "Days without a valuation before flagging a portfolio company (default 90)" },
      { name: "stale_fx_days",              field_type: "NumberField", label: "Stale FX rate (days)",       meta_data: "",       position: 6,
        help_text: "Days since last FX rate update before flagging (default 30)" },
      { name: "email",                      field_type: "TextField",   label: "Report recipient email(s)",  meta_data: "",       position: 7,
        help_text: "Comma-separated email addresses for the quality report" }
    ]
  },

  # --- PresentationAnalystAgent ---
  {
    name: "SupportAgent", tag: "PresentationAnalystAgent",
    fields: [
      { name: "presentation_doc_names", field_type: "TextField", label: "Presentation document names", position: 1,
        meta_data: "",
        help_text: "Comma-separated document names to match (e.g. Investor Update, Board Deck). Case-insensitive partial match." },
      { name: "max_periods",            field_type: "NumberField", label: "Max periods to analyse",    position: 2,
        meta_data: "",
        help_text: "Number of most recent Actual KPI periods to include (default 8)." },
      { name: "kpi_tag_list",           field_type: "TextField",   label: "KPI tag filter",             position: 3,
        meta_data: "",
        help_text: "Tag used to filter KPI reports (default: Actual)." },
      { name: "comparison_strategy",    field_type: "Select",      label: "Comparison strategy",        position: 4,
        meta_data: "all_periods,sliding_window",
        help_text: "all_periods: one LLM call across all periods (more accurate). sliding_window: one call per adjacent pair (cheaper)." },
      { name: "enable_scoring",         field_type: "Select",      label: "Enable Management Accountability Score", position: 5,
        meta_data: "Yes,No",
        help_text: "When set to No, skips the Management Accountability Score computation and hides the score section in the UI." },
      { name: "enable_questions",       field_type: "Select",      label: "Enable pre-board briefing questions",    position: 6,
        meta_data: "Yes,No",
        help_text: "When set to No, skips the analyst question generation step and hides the briefing section in the UI." }
    ]
  },

  # --- PortfolioScoringAgent ---
  # Skill files (File fields) are uploaded manually per sector after seeding.
  # Add one File field per sector needed; meta_data drives skill_for_sector matching.
  {
    name: "SupportAgent", tag: "PortfolioScoringAgent",
    fields: [
      { name: "generic_skill_file",       field_type: "File",        label: "Generic Portfolio Skill",     position: 1,
        meta_data: "skill: true, sector: General",
        help_text: "Fallback skill prompt used when no sector-specific file is configured." },
      { name: "beauty_skincare_skill",    field_type: "File",        label: "Beauty & Skincare Skill",     position: 2,
        meta_data: "skill: true, sector: Beauty & Skincare",
        help_text: "Sector skill prompt for Beauty & Skincare portfolio companies." },
      { name: "min_points_per_section",   field_type: "NumberField", label: "Min Points Per Section",      position: 3,
        meta_data: "",
        help_text: "Minimum positives/concerns per dimension and minimum items in Strengths, Risks, Recommendations. Default: 3" },
      { name: "kpi_frequency",            field_type: "Select",      label: "KPI Frequency Filter",        position: 4,
        meta_data: "All,Month,Quarter,Half Year,Year,YTD",
        help_text: "Filter KPI reports by period type when scoring. 'All' includes every period." },
      { name: "docs_from_last_n_reports", field_type: "NumberField", label: "Docs From Last N Reports",    position: 5,
        meta_data: "",
        help_text: "Number of recent Actual KPI reports to pull documents from (default: 1)." },
      { name: "document_name_filter",     field_type: "TextField",   label: "Document Name Filter",        position: 6,
        meta_data: "",
        help_text: "Comma-separated document names to include. Leave blank to use all documents from the selected reports." }
    ]
  }
]

form_type_ids = {}

new_form_types.each do |ft_config|
  ft = FormType.find_or_initialize_by(entity_id: ENTITY_ID, name: ft_config[:name], tag: ft_config[:tag])
  if ft.new_record?
    ft.save!
    puts "Created FormType #{ft.id}: #{ft.name} tag=#{ft.tag}"
  else
    puts "FormType already exists: #{ft.id}: #{ft.name} tag=#{ft.tag}"
  end

  form_type_ids[ft_config[:tag]] = ft.id

  ft_config[:fields].each do |field_attrs|
    next if ft.form_custom_fields.exists?(name: field_attrs[:name])
    ft.form_custom_fields.create!(field_attrs)
    puts "  Added field '#{field_attrs[:name]}' (#{field_attrs[:field_type]})"
  end
end

# ---------------------------------------------------------------------------
# 3. Create SupportAgent records for entity 157
# ---------------------------------------------------------------------------

# Look up FormType IDs (existing + newly created)
kyc_ft_id      = 90
portco_ft_id   = 91
dist_ft_id     = form_type_ids["DistributionReadinessAgent"]
esign_ft_id    = form_type_ids["EsignMonitorAgent"]
dq_ft_id       = form_type_ids["DataQualityAgent"]
scoring_ft_id  = form_type_ids["PortfolioScoringAgent"]

agents_config = [
  # --- KYC Expiry extension of existing KycOnboardingAgent ---
  # Update the existing Kyc Agent 1 (id=1) with the new expiry fields rather than creating a duplicate
  {
    update_existing_id: 1,
    extra_json_fields: {
      "check_expiry"        => "Yes",
      "expiry_warning_days" => "60,30,15"
    }
  },

  # --- KPI Reminder extension of existing PortfolioCompanyAgent (id=3) ---
  {
    update_existing_id: 3,
    extra_json_fields: {
      "send_kpi_reminder" => "Yes",
      "reminder_days"     => "7,14,21"
    }
  },

  # --- New: DistributionReadinessAgent ---
  {
    name:         "Distribution Readiness",
    agent_type:   "DistributionReadinessAgent",
    form_type_id: dist_ft_id,
    with_steps:   true,
    enabled:      true,
    json_fields: {
      "check_kyc"            => "Yes",
      "check_net_payable"    => "Yes",
      "check_docs_generated" => "Yes",
      "check_docs_approved"  => "Yes",
      "check_bank_details"   => "Yes"
    },
    schedule: nil   # on-demand only
  },

  # --- New: EsignMonitorAgent ---
  {
    name:         "E-Sign Monitor",
    agent_type:   "EsignMonitorAgent",
    form_type_id: esign_ft_id,
    with_steps:   false,
    enabled:      true,
    json_fields: {
      "send_reminders"      => "Yes",
      "flag_expired"        => "Yes",
      "reminder_after_days" => "3"
    },
    schedule: {
      frequency:              "daily",
      run_at_time:            "08:00",
      timezone:               "Asia/Kolkata",
      enabled:                true,
      notify_on_failure:      true,
      notify_on_success:      false,
      notify_on_partial_success: true,
      notify_caphive_on_error: true
    }
  },

  # --- New: PortfolioScoringAgent ---
  # Skill files must be uploaded manually via the agent edit page after seeding.
  # json_fields below set the runtime defaults; override via the UI as needed.
  {
    name:         "Portfolio Scoring Agent",
    agent_type:   "PortfolioScoringAgent",
    form_type_id: scoring_ft_id,
    with_steps:   false,
    enabled:      true,
    json_fields: {
      "min_points_per_section"   => "5",
      "kpi_frequency"            => "All",
      "docs_from_last_n_reports" => 3,
      "document_name_filter"     => ""
    },
    schedule: nil  # on-demand and scheduled via rake task; no AgentSchedule needed
  },

  # --- New: DataQualityAgent ---
  {
    name:         "Data Quality",
    agent_type:   "DataQualityAgent",
    form_type_id: dq_ft_id,
    with_steps:   false,
    enabled:      true,
    json_fields: {
      "check_commitment_overflows" => "Yes",
      "check_missing_valuations"   => "Yes",
      "check_stale_fx_rates"       => "Yes",
      "send_report"                => "Yes",
      "stale_valuation_days"       => "90",
      "stale_fx_days"              => "30",
      "email"                      => "thimmaiah@gmail.com"
    },
    schedule: {
      frequency:              "daily",
      run_at_time:            "01:00",
      timezone:               "Asia/Kolkata",
      enabled:                true,
      notify_on_failure:      true,
      notify_on_success:      false,
      notify_on_partial_success: true,
      notify_caphive_on_error: true
    }
  }
]

agents_config.each do |cfg|
  # Handle updates to existing agents
  if cfg[:update_existing_id]
    sa = SupportAgent.find_by(id: cfg[:update_existing_id])
    unless sa
      puts "SupportAgent #{cfg[:update_existing_id]} not found — skipping update"
      next
    end
    merged = (sa.json_fields || {}).merge(cfg[:extra_json_fields])
    sa.update!(json_fields: merged)
    puts "Updated SupportAgent #{sa.id} (#{sa.name}) with: #{cfg[:extra_json_fields].keys.join(', ')}"
    next
  end

  # Create new agent (idempotent on name + entity_id + agent_type)
  sa = SupportAgent.find_or_initialize_by(
    entity_id:  ENTITY_ID,
    agent_type: cfg[:agent_type],
    name:       cfg[:name]
  )

  sa.assign_attributes(
    form_type_id: cfg[:form_type_id],
    with_steps:   cfg[:with_steps],
    enabled:      cfg[:enabled],
    json_fields:  (sa.json_fields || {}).merge(cfg[:json_fields])
  )
  sa.save!
  puts "#{sa.new_record? ? 'Created' : 'Updated'} SupportAgent #{sa.id}: #{sa.name} (#{sa.agent_type})"

  # Create schedule if specified
  if cfg[:schedule]
    sch = AgentSchedule.find_or_initialize_by(support_agent_id: sa.id)
    sch.assign_attributes(
      entity_id:                   ENTITY_ID,
      **cfg[:schedule]
    )
    sch.next_run_at ||= Time.zone.now.end_of_day
    sch.save!
    puts "  Schedule: #{sch.frequency} at #{sch.run_at_time} #{sch.timezone}"
  end
end

puts "\nDone."
