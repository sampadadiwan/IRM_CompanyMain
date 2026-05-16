# Rake tasks for managing SupportAgent provisioning across entities.
#
# Usage:
#   rake support_agents:clone[TARGET_ENTITY_ID]
#   rake support_agents:clone[TARGET_ENTITY_ID,SOURCE_ENTITY_ID]   # defaults source to 157
#
# What it does:
#   1. Enables all support_agent bitflags that the source entity has
#   2. For each SupportAgent on the source entity:
#      a. Clones the FormType (name + tag) for the target entity
#      b. Clones every FormCustomField on that FormType (preserving values)
#      c. Clones the SupportAgent itself (name, description, agent_type, model, json_fields)
#      d. For every File-type custom field, copies the attached Document to the new agent
#   3. Skips records that already exist on the target entity (idempotent)

namespace :support_agents do
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
