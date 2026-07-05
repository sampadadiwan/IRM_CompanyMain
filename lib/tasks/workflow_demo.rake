namespace :workflow_demo do
  # Shared name constants so setup and teardown target the same records.
  WORKFLOW_DEMO_TEMPLATE_NAME = "Two-Stage LP Review (Demo)"
  WORKFLOW_DEMO_FOLDER_NAME   = "Q3 2026 LP Data Room (Demo)"

  desc <<~DESC
    Seed a sample "Two-Stage LP Review" workflow template, a "Q3 2026 LP Data Room"
    folder with 4 sample documents, and (optionally) launch the workflow.

    Usage:
      rake 'workflow_demo:setup[ENTITY_ID]'              # assign template to folder, no launch
      rake 'workflow_demo:setup[ENTITY_ID,launch]'       # assign + launch (notifies step-1 actors)

    The task is idempotent: it tears down and recreates the demo template and folder by name.
  DESC
  task :setup, [:entity_id, :launch] => :environment do |_, args|
    entity_id = args[:entity_id].to_i
    abort "Usage: rake 'workflow_demo:setup[ENTITY_ID]'" if entity_id.zero?

    entity = Entity.find_by(id: entity_id) || abort("Entity #{entity_id} not found")
    admin  = entity.employees.with_role(:company_admin).first ||
             entity.employees.first
    abort "No employees found for entity #{entity_id}" if admin.nil?

    # Need at least two employees to act as reviewers across the two steps.
    reviewers = entity.employees.to_a
    actor1    = reviewers[0]        # step-1 actor (may be same as admin)
    actor2    = reviewers[1] || reviewers[0]  # step-2 actor

    log = ->(msg) { puts "[workflow_demo] #{msg}" }

    log.call("Entity: #{entity.name} (id=#{entity_id})")
    log.call("Admin : #{admin.email}")
    log.call("Actor1: #{actor1.email}")
    log.call("Actor2: #{actor2.email}")

    template_name = WORKFLOW_DEMO_TEMPLATE_NAME
    folder_name   = WORKFLOW_DEMO_FOLDER_NAME

    # ── Tear down any previous demo run ──────────────────────────────────────
    if (existing_template = WorkflowTemplate.find_by(entity: entity, name: template_name))
      log.call("Removing existing template '#{template_name}' (id=#{existing_template.id})")
      existing_template.destroy!
    end

    root_folder = entity.folders.find_by(level: 0)
    abort "No root folder found for entity #{entity_id}" unless root_folder

    if (existing_folder = root_folder.children.find_by(name: folder_name))
      # Archive any active workflow instances so the folder can be destroyed cleanly
      existing_folder.workflow_instances.instance_active.each do |inst|
        log.call("Archiving active workflow instance ##{inst.id} on existing folder")
        inst.instance_archived!
      end
      log.call("Removing existing folder '#{folder_name}' (id=#{existing_folder.id})")
      existing_folder.destroy!
    end

    # ── Create workflow template ──────────────────────────────────────────────
    log.call("\nCreating template: #{template_name}")

    template = WorkflowTemplate.create!(
      entity:                  entity,
      name:                    template_name,
      description:             "Demo two-stage review: Initial LP Review followed by Final Approval. " \
                               "Used to walk through the folder workflow lifecycle.",
      reminder_interval_days:  3,
      attach_document_in_email: false
    )
    log.call("  Template##{template.id} created")

    # Step 1 — Initial LP Review (any_one quorum, stop on reject)
    step1 = template.workflow_steps.create!(
      position:        1,
      name:            "Initial LP Review",
      description:     "LP reviewers verify the completeness of the data room before advancing " \
                       "to final approval. Any one reviewer may approve on behalf of the group.",
      states:          "Approved,Rejected,Needs More Info",
      quorum_rule:     :any_one,
      on_reject_rule:  :stop
    )
    step1.workflow_step_actors.create!(user: actor1)
    log.call("  Step 1 '#{step1.name}' — actor: #{actor1.email}")

    # Step 2 — Final Approval (all quorum, previous_step on reject)
    step2 = template.workflow_steps.create!(
      position:        2,
      name:            "Final Approval",
      description:     "All assigned approvers must agree before the data room is considered " \
                       "fully approved. A rejection sends the workflow back to the previous step.",
      states:          "Approved,Rejected,Tentative",
      quorum_rule:     :all,
      on_reject_rule:  :previous_step,
      reminder_interval_days: 5   # override template-level 3-day interval for this step
    )
    step2.workflow_step_actors.create!(user: actor1)
    step2.workflow_step_actors.create!(user: actor2) if actor2.id != actor1.id
    log.call("  Step 2 '#{step2.name}' — actors: #{[actor1, actor2].uniq(&:id).map(&:email).join(', ')}")

    # ── Create folder with sample documents ──────────────────────────────────
    log.call("\nCreating folder: #{folder_name}")

    folder = Folder.create!(
      entity:            entity,
      name:              folder_name,
      parent:            root_folder,
      workflow_template: template
    )
    log.call("  Folder##{folder.id} created, template assigned")

    sample_docs = [
      { name: "Q3 Financial Statements",    file: "CashFlow.xlsx"                           },
      { name: "Cap Table — Q3 2026",        file: "CRISIL Report.xlsx"                      },
      { name: "Investment Summary (Draft)",  file: "Offer_1_SPA.pdf"                         },
      { name: "Subscription Agreement",     file: "Commitment Agreement Template.docx"      }
    ]

    sample_docs.each do |doc_attrs|
      path = Rails.root.join("public/sample_uploads/#{doc_attrs[:file]}")
      unless File.exist?(path)
        log.call("  WARN: sample file not found, skipping: #{path}")
        next
      end

      doc = Document.create!(
        entity:    entity,
        folder:    folder,
        name:      doc_attrs[:name],
        user:      admin,
        send_email: false,
        file:      File.open(path, "rb")
      )
      log.call("  Document##{doc.id} '#{doc.name}' attached")
    rescue StandardError => e
      log.call("  WARN: could not attach '#{doc_attrs[:name]}': #{e.message}")
    end

    # ── Optionally launch the workflow ────────────────────────────────────────
    if args[:launch].to_s.strip.downcase == "launch"
      log.call("\nLaunching workflow instance...")
      instance = WorkflowInstanceLaunch.call(workflowable: folder, launched_by: admin)[:instance]
      log.call("  WorkflowInstance##{instance.id} launched — status=#{instance.status}, step=#{instance.current_step_position}")
      log.call("  Step-activation emails enqueued for step-1 actors.")
    else
      log.call("\nWorkflow NOT launched (pass 'launch' as second arg to auto-launch).")
      log.call("  To launch manually in Rails console:")
      log.call("  WorkflowInstanceLaunch.call(workflowable: Folder.find(#{folder.id}), launched_by: User.find(#{admin.id}))")
    end

    # ── Summary ───────────────────────────────────────────────────────────────
    log.call("\n#{'=' * 60}")
    log.call("Demo setup complete for entity: #{entity.name}")
    log.call("  Template : #{template.name} (id=#{template.id})")
    log.call("  Folder   : #{folder.name} (id=#{folder.id})")
    log.call("  Documents: #{folder.documents.count}")
    log.call("  Steps    : #{template.workflow_steps.count}")
    log.call("  Admin UI : /admin/workflow_templates/#{template.id}/edit")
    log.call("#{'=' * 60}")

  rescue StandardError => e
    puts e.message
    puts e.backtrace.join("\n")
    raise e
  end

  desc "Tear down the demo workflow template and folder for ENTITY_ID. Idempotent."
  task :teardown, [:entity_id] => :environment do |_, args|
    entity_id = args[:entity_id].to_i
    abort "Usage: rake 'workflow_demo:teardown[ENTITY_ID]'" if entity_id.zero?

    entity = Entity.find_by(id: entity_id) || abort("Entity #{entity_id} not found")
    log = ->(msg) { puts "[workflow_demo] #{msg}" }

    folder = entity.folders.find_by(name: WORKFLOW_DEMO_FOLDER_NAME)
    if folder
      folder.workflow_instances.instance_active.each { |i| i.instance_archived! }
      folder.destroy!
      log.call("Folder '#{WORKFLOW_DEMO_FOLDER_NAME}' destroyed")
    else
      log.call("Folder '#{WORKFLOW_DEMO_FOLDER_NAME}' not found — skipping")
    end

    template = WorkflowTemplate.find_by(entity: entity, name: WORKFLOW_DEMO_TEMPLATE_NAME)
    if template
      template.destroy!
      log.call("Template '#{WORKFLOW_DEMO_TEMPLATE_NAME}' destroyed")
    else
      log.call("Template '#{WORKFLOW_DEMO_TEMPLATE_NAME}' not found — skipping")
    end

    log.call("Teardown complete.")
  rescue StandardError => e
    puts e.message
    puts e.backtrace.join("\n")
    raise e
  end
end
