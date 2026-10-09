# LP CRM MVP (docs/modules/investors/lp_relationship_crm_alt_mvp_prd.md)
#
# Seeds the CRM custom fields for one entity:
#   - "InvestorAccess" form type: contact/touch-point fields (designation, POC role,
#     intro, LinkedIn, primary-contact flag)
#   - "Investor" form type: LP-level fields (engagement status, relationship owner)
#
# The whole CRM is custom-field driven, so this task is the only "setup" a tenant
# needs — everything else (forms, show pages, ransack filters) picks the fields up
# automatically via WithCustomField.
#
# Idempotent: fields are looked up by their normalized name and only created when
# missing. Existing fields are left untouched so tenant edits (renamed labels,
# extra options, reordered positions) are never clobbered by a re-run.
#
# Usage:
#   bundle exec rake lp_crm:seed_custom_fields[ENTITY_ID]

namespace :lp_crm do
  desc "Seed LP CRM custom fields (InvestorAccess contact fields + Investor engagement fields) for an entity"
  task :seed_custom_fields, [:entity_id] => :environment do |_, args|
    entity_id = args[:entity_id]&.to_i
    abort "Usage: rake lp_crm:seed_custom_fields[ENTITY_ID]" if entity_id.blank? || entity_id.zero?

    entity = Entity.find_by(id: entity_id)
    abort "Entity #{entity_id} not found" unless entity

    puts "Seeding LP CRM custom fields for entity: #{entity.name} (id=#{entity.id})"

    # Field definitions per form type. Keys:
    #   label      — human label shown on forms (name is derived from it)
    #   field_type — one of FormCustomField::VALID_FIELD_TYPES
    #   meta_data  — comma-separated options (Select fields only)
    #   help_text  — small print under the input
    #   filter     — mark the field filterable in list searches (register_cf_ransackers)
    seeds = {
      # Touch-point (contact) fields — rendered on the stakeholder access form
      "InvestorAccess" => [
        { label: "Designation", field_type: "TextField",
          help_text: "Job title at the LP, e.g. CFO" },
        { label: "POC Role", field_type: "Select", filter: true,
          meta_data: "Decision Maker,Finance,Documentation,Legal,Operations,Other",
          help_text: "What this person handles in the relationship" },
        { label: "Intro", field_type: "TextArea",
          help_text: "Relationship context: how we know them, who introduced us, what they care about" },
        { label: "LinkedIn", field_type: "TextField",
          validation_rules: { "format" => "url" },
          help_text: "LinkedIn profile URL" },
        { label: "Primary Contact", field_type: "CheckBox",
          help_text: "The main point of contact at this LP" }
      ],
      # LP-level fields — rendered on the stakeholder (Investor) form
      "Investor" => [
        { label: "Engagement Status", field_type: "Select", filter: true,
          meta_data: "Identified,Contacted,In Discussion,Due Diligence,Soft Commit,Committed,Passed",
          help_text: "Where the relationship stands in the fund-raise pipeline" },
        { label: "Relationship Owner", field_type: "TextField", filter: true,
          help_text: "The team member accountable for this LP relationship" }
      ]
    }

    seeds.each do |form_type_name, fields|
      # Same lookup WithCustomField#setup_form_type uses (last matching by name),
      # so the fields land on the form type the models will actually resolve to.
      form_type = entity.form_types.where(name: form_type_name).last ||
                  entity.form_types.create!(name: form_type_name)
      puts "  Form type: #{form_type_name} (id=#{form_type.id})"

      fields.each do |f|
        # Field keys are stored normalized (e.g. "POC Role" -> "poc_role"); use the
        # same normalizer as imports so lookups match however the field was created.
        name = FormCustomField.to_name(f[:label])
        existing = form_type.form_custom_fields.find_by(name:)
        if existing
          puts "    [SKIP] #{f[:label]} (#{name}) already exists"
          next
        end

        form_type.form_custom_fields.create!(
          name:,
          label: f[:label],
          field_type: f[:field_type],
          meta_data: f[:meta_data],
          help_text: f[:help_text],
          validation_rules: f[:validation_rules],
          # filter_in_search drives FormCustomField.filterable, which is what
          # registers the field as a ransack filter in list views.
          filter_in_search: f[:filter] == true,
          required: false # CRM fields are always optional — contacts are often added with partial info
        )
        puts "    [ADD]  #{f[:label]} (#{name}, #{f[:field_type]})"
      end
    end

    puts "Done."
  end
end
