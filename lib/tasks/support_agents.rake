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

# ---------------------------------------------------------------------------
# FormType + field definitions (entity-agnostic; IDs are resolved at runtime)
# ---------------------------------------------------------------------------
SUPPORT_AGENT_FORM_CONFIGS = [
  # Existing agent FormTypes that need extra fields added
  {
    tag: "KycOnboardingAgent",
    extend_only: true,  # FormType already exists; only ensure missing fields
    fields: [
      { name: "check_expiry",        field_type: "Select",      label: "Check expiry status",
        meta_data: "Yes,No", position: 8 },
      { name: "expiry_warning_days", field_type: "TextField",   label: "Expiry warning days",
        meta_data: "", position: 9,
        help_text: "Comma-separated day thresholds before expiry to warn, e.g. 60,30,15" }
    ]
  },
  {
    tag: "PortfolioCompanyAgent",
    extend_only: true,
    fields: [
      { name: "send_kpi_reminder", field_type: "Select",    label: "Send KPI reminder",
        meta_data: "Yes,No", position: 7 },
      { name: "reminder_days",     field_type: "TextField", label: "Reminder days",
        meta_data: "", position: 8,
        help_text: "Comma-separated day offsets from period start to send reminders, e.g. 7,14,21" }
    ]
  },

  # New agent FormTypes (created fresh when missing)
  {
    tag: "DistributionReadinessAgent",
    agent: {
      name:        "Distribution Readiness",
      with_steps:  true,
      json_fields: {
        "check_kyc"            => "Yes",
        "check_net_payable"    => "Yes",
        "check_docs_generated" => "Yes",
        "check_docs_approved"  => "Yes",
        "check_bank_details"   => "Yes"
      }
    },
    fields: [
      { name: "check_kyc",            field_type: "Select", label: "Check investor KYC",         meta_data: "Yes,No", position: 1 },
      { name: "check_net_payable",    field_type: "Select", label: "Check net payable computed",  meta_data: "Yes,No", position: 2 },
      { name: "check_docs_generated", field_type: "Select", label: "Check notices generated",     meta_data: "Yes,No", position: 3 },
      { name: "check_docs_approved",  field_type: "Select", label: "Check notices approved",      meta_data: "Yes,No", position: 4 },
      { name: "check_bank_details",   field_type: "Select", label: "Check bank details",          meta_data: "Yes,No", position: 5 }
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
      { name: "send_reminders",      field_type: "Select",      label: "Send e-sign reminders",  meta_data: "Yes,No", position: 1 },
      { name: "flag_expired",        field_type: "Select",      label: "Flag expired documents",  meta_data: "Yes,No", position: 2 },
      { name: "reminder_after_days", field_type: "NumberField", label: "Reminder after (days)",   meta_data: "",       position: 3,
        help_text: "Days a document stays in 'requested' before a resend is triggered (default 3)" }
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
      { name: "check_commitment_overflows", field_type: "Select",      label: "Check commitment overflows",  meta_data: "Yes,No", position: 1 },
      { name: "check_missing_valuations",   field_type: "Select",      label: "Check missing valuations",    meta_data: "Yes,No", position: 2 },
      { name: "check_stale_fx_rates",       field_type: "Select",      label: "Check stale FX rates",        meta_data: "Yes,No", position: 3 },
      { name: "send_report",                field_type: "Select",      label: "Send quality report email",   meta_data: "Yes,No", position: 4 },
      { name: "stale_valuation_days",       field_type: "NumberField", label: "Stale valuation (days)",      meta_data: "",       position: 5,
        help_text: "Days without a valuation before flagging a portfolio company (default 90)" },
      { name: "stale_fx_days",              field_type: "NumberField", label: "Stale FX rate (days)",        meta_data: "",       position: 6,
        help_text: "Days since last FX rate update before flagging (default 30)" },
      { name: "email",                      field_type: "TextField",   label: "Report recipient email(s)",   meta_data: "",       position: 7,
        help_text: "Comma-separated email addresses for the quality report" }
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
      # No schedule — triggered on-demand or via rake task
    },
    fields: [
      # Skill files are uploaded manually via the agent edit page after seeding.
      # Add one File field per sector; meta_data drives skill_for_sector matching.
      { name: "generic_skill_file",       field_type: "File",        label: "Generic Portfolio Skill",
        position: 1, meta_data: "skill: true, sector: General",
        help_text: "Fallback skill prompt used when no sector-specific file is configured." },
      { name: "beauty_skincare_skill",    field_type: "File",        label: "Beauty & Skincare Skill",
        position: 2, meta_data: "skill: true, sector: Beauty & Skincare",
        help_text: "Sector skill prompt for Beauty & Skincare portfolio companies." },
      { name: "min_points_per_section",   field_type: "NumberField", label: "Min Points Per Section",
        position: 3, meta_data: "",
        help_text: "Minimum positives/concerns per dimension and minimum items in Strengths, Risks, Recommendations. Default: 3" },
      { name: "kpi_frequency",            field_type: "Select",      label: "KPI Frequency Filter",
        position: 4, meta_data: "All,Month,Quarter,Half Year,Year,YTD",
        help_text: "Filter KPI reports by period type when scoring. 'All' includes every period." },
      { name: "docs_from_last_n_reports", field_type: "NumberField", label: "Docs From Last N Reports",
        position: 5, meta_data: "",
        help_text: "Number of recent Actual KPI reports to pull documents from (default: 1)." },
      { name: "document_name_filter",     field_type: "TextField",   label: "Document Name Filter",
        position: 6, meta_data: "",
        help_text: "Comma-separated document names to include. Leave blank to use all documents from the selected reports." }
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

      # 2. Ensure each custom field exists on this FormType
      cfg[:fields].each do |field_attrs|
        if ft.form_custom_fields.exists?(name: field_attrs[:name])
          puts "    [fcf] '#{field_attrs[:name]}' — already exists"
        else
          ft.form_custom_fields.create!(field_attrs)
          puts "    [fcf] '#{field_attrs[:name]}' (#{field_attrs[:field_type]}) — created"
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
      report_analysis_agent portfolio_scoring_agent
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
