namespace :workflow_seeds do
  desc <<~DESC
    Seed meaningful workflow templates for Folder, InvestorKyc, and Approval
    workflowable types for a given entity.

    Usage:
      rake 'workflow_seeds:seed[ENTITY_ID]'

    Idempotent: each template is identified by name + entity. Re-running skips
    any template that already exists. Run workflow_seeds:teardown first if you
    want to replace a template.
  DESC
  task :seed, [:entity_id] => :environment do |_, args|
    entity_id = args[:entity_id].to_i
    abort "Usage: rake 'workflow_seeds:seed[ENTITY_ID]'" if entity_id.zero?

    entity = Entity.find_by(id: entity_id) || abort("Entity #{entity_id} not found")
    log    = ->(msg) { puts "[workflow_seeds] #{msg}" }

    # Use the first two employees as default actors across all templates.
    employees = entity.employees.to_a
    abort "No employees found for entity #{entity_id}" if employees.empty?
    actor1 = employees[0]
    actor2 = employees[1] || employees[0]

    log.call("Entity : #{entity.name} (id=#{entity_id})")
    log.call("Actor1 : #{actor1.email}")
    log.call("Actor2 : #{actor2.email}")
    log.call("")

    created = 0
    skipped = 0

    # Helper: find-or-skip a template by name, yield to build steps only when new.
    create_template = lambda do |name, attrs, &block|
      existing = WorkflowTemplate.find_by(entity: entity, name: name)
      if existing
        log.call("SKIP  #{name} (id=#{existing.id}) — already exists")
        skipped += 1
        next
      end

      template = WorkflowTemplate.create!(attrs.merge(entity: entity, name: name))
      log.call("CREATE #{name} (id=#{template.id})")
      block.call(template)
      created += 1
    end

    # Helper: add a step with named actors.
    add_step = lambda do |template, pos, step_name, actors, step_attrs = {}|
      step = template.workflow_steps.create!(
        { position: pos, name: step_name }.merge(step_attrs)
      )
      actors.each { |u| step.workflow_step_actors.create!(user: u) }
      log.call("         Step #{pos}: #{step_name} — actors: #{actors.map(&:email).join(', ')}")
    end

    # ── Folder templates ──────────────────────────────────────────────────────

    log.call("── Folder workflows ──────────────────────────────────────")

    create_template.call(
      "LP Data Room Review",
      workflowable_type:        "Folder",
      description:              "Two-stage review for LP data rooms. " \
                                "A reviewer verifies completeness before the full IC signs off.",
      reminder_interval_days:   3,
      attach_document_in_email: false
    ) do |t|
      add_step.call(t, 1, "Completeness Check", [actor1],
        states:          "Approved,Needs More Info,Rejected",
        quorum_rule:     :any_one,
        on_reject_rule:  :stop,
        description:     "Verify all required documents are present and legible before escalating to IC.")
      add_step.call(t, 2, "IC Sign-off", [actor1, actor2].uniq(&:id),
        states:          "Approved,Rejected,Tentative",
        quorum_rule:     :all,
        on_reject_rule:  :previous_step,
        description:     "All IC members must approve. A rejection returns the room to the Completeness Check step.")
    end

    create_template.call(
      "Regulatory Filing Review",
      workflowable_type:        "Folder",
      description:              "Single-step sign-off confirming that all regulatory filings " \
                                "in this folder have been reviewed and are ready for submission.",
      reminder_interval_days:   2,
      attach_document_in_email: true
    ) do |t|
      add_step.call(t, 1, "Compliance Sign-off", [actor1],
        states:          "Cleared,Requires Revision,Rejected",
        quorum_rule:     :any_one,
        on_reject_rule:  :stop,
        description:     "Confirm filings are complete and accurate before submission to the regulator.")
    end

    # ── InvestorKyc templates ─────────────────────────────────────────────────
    #
    # Three templates covering the three natural trigger points in the KYC lifecycle.
    # Each has its own auto-assignment rule so the right workflow fires automatically.
    # In practice an entity will use ONE of these depending on their process:
    #   - "KYC Onboarding Kick-off"       → for teams that start work immediately on creation
    #   - "KYC Submission Review"          → for teams that review after investor submits
    #   - "Post-Verification Audit"        → for teams that run a compliance audit after sign-off
    #
    # Because the idempotency guard prevents re-assignment once a template is set,
    # delete the two rules your entity does NOT use after seeding.

    log.call("")
    log.call("── InvestorKyc workflows ─────────────────────────────────")

    # ── Template 1: fires the moment a KYC record is created ──────────────────
    # Use this when the fund team needs to coordinate investor outreach and
    # document collection tasks in parallel with the investor filling in the form.

    create_template.call(
      "KYC Onboarding Kick-off",
      workflowable_type:        "InvestorKyc",
      description:              "Kicks off the moment a KYC record is opened for a new investor. " \
                                "Tracks internal tasks: sending the form link, following up, " \
                                "and confirming the investor has everything they need to complete submission.",
      reminder_interval_days:   2,
      attach_document_in_email: false
    ) do |t|
      add_step.call(t, 1, "Investor Outreach", [actor1],
        states:          "Link Sent,No Response,Declined",
        quorum_rule:     :any_one,
        on_reject_rule:  :stop,
        description:     "Send the KYC form link and onboarding instructions to the investor. " \
                         "Mark 'No Response' if no acknowledgement within the reminder window.")
      add_step.call(t, 2, "Document Checklist Briefing", [actor1],
        states:          "Briefed,Queries Pending,Not Required",
        quorum_rule:     :any_one,
        on_reject_rule:  :previous_step,
        description:     "Confirm the investor understands which documents are required " \
                         "(PAN, ID proof, address proof, bank details). Resolve any queries before they submit.")
      add_step.call(t, 3, "Submission Readiness Confirmation", [actor2],
        states:          "Ready to Submit,Follow-up Required",
        quorum_rule:     :any_one,
        on_reject_rule:  :previous_step,
        description:     "Relationship manager confirms the investor is ready to submit and " \
                         "all outstanding queries have been addressed.")
    end

    # Catch-all rule: assign to every new InvestorKyc regardless of its attributes.
    t1 = WorkflowTemplate.find_by(entity: entity, name: "KYC Onboarding Kick-off")
    if t1 && WorkflowAutoAssignmentRule.where(entity: entity, workflow_template: t1).none?
      WorkflowAutoAssignmentRule.create!(
        entity:            entity,
        workflow_template: t1,
        workflowable_type: "InvestorKyc",
        conditions:        [],         # fires for every new KYC
        auto_launch:       true,
        priority:          0,
        created_by:        actor1
      )
      log.call("         Auto-assignment rule: on create (catch-all)")
    end

    # ── Template 2: fires when the investor marks the form as complete ─────────
    # Use this when the fund team's review process begins only after the investor
    # has finished filling in the form (completed_by_investor = true).

    create_template.call(
      "KYC Submission Review",
      workflowable_type:        "InvestorKyc",
      description:              "Triggered automatically when the investor marks their KYC as complete. " \
                                "Runs the fund's three-stage internal review: document verification, " \
                                "AML/sanctions screening, and final compliance approval.",
      reminder_interval_days:   2,
      attach_document_in_email: true
    ) do |t|
      add_step.call(t, 1, "Document Verification", [actor1],
        states:          "Verified,Incomplete,Rejected",
        quorum_rule:     :any_one,
        on_reject_rule:  :stop,
        description:     "Verify that PAN card, identity proof, address proof, and bank account details " \
                         "are present, legible, and match the investor's declaration. Reject if any are missing.")
      add_step.call(t, 2, "AML & Sanctions Screening", [actor1],
        states:          "Cleared,Adverse Match Found,Under Investigation",
        quorum_rule:     :any_one,
        on_reject_rule:  :stop,
        description:     "Screen the investor against sanctions lists (OFAC, UN, EU), PEP databases, " \
                         "and internal AML rules. Flag any adverse matches for escalation.")
      add_step.call(t, 3, "Compliance Head Approval", [actor2],
        states:          "Approved,Rejected",
        quorum_rule:     :any_one,
        on_reject_rule:  :restart,
        description:     "Compliance head gives final approval. A rejection restarts the review " \
                         "from document verification so all stages are re-confirmed.")
    end

    # Condition: fires only when completed_by_investor changes to true.
    t2 = WorkflowTemplate.find_by(entity: entity, name: "KYC Submission Review")
    if t2 && WorkflowAutoAssignmentRule.where(entity: entity, workflow_template: t2).none?
      WorkflowAutoAssignmentRule.create!(
        entity:            entity,
        workflow_template: t2,
        workflowable_type: "InvestorKyc",
        conditions:        [{ "attribute" => "completed_by_investor", "operator" => "eq", "value" => "true" }],
        auto_launch:       true,
        priority:          0,
        created_by:        actor1
      )
      log.call("         Auto-assignment rule: completed_by_investor = true")
    end

    # ── Template 3: fires once the KYC is formally verified ───────────────────
    # Use this when the fund runs a post-verification compliance audit to confirm
    # the record is ready for regulatory reporting and long-term archival.

    create_template.call(
      "Post-Verification KYC Audit",
      workflowable_type:        "InvestorKyc",
      description:              "Triggered when a KYC record is marked as verified. " \
                                "Runs a final compliance audit to confirm the file is complete, " \
                                "free of exceptions, and ready for regulatory reporting and archival.",
      reminder_interval_days:   5,
      attach_document_in_email: false
    ) do |t|
      add_step.call(t, 1, "Compliance File Audit", [actor2],
        states:          "Audit Passed,Exceptions Found,Audit Failed",
        quorum_rule:     :any_one,
        on_reject_rule:  :stop,
        description:     "Compliance team reviews the fully verified KYC file end-to-end: " \
                         "checks for completeness, consistency, and any outstanding AML exceptions " \
                         "before confirming the investor may proceed to onboarding.")
      add_step.call(t, 2, "Regulatory Reporting Sign-off", [actor2],
        states:          "Confirmed,Deferred,Not Required",
        quorum_rule:     :any_one,
        on_reject_rule:  :stop,
        description:     "Compliance officer signs off that this KYC is reportable under applicable " \
                         "regulations (PMLA, FATF, etc.) and authorises it for inclusion in the next " \
                         "regulatory filing or annual KYC refresh schedule.")
      add_step.call(t, 3, "Record Archival Confirmation", [actor1],
        states:          "Archived,Pending Archival",
        quorum_rule:     :any_one,
        on_reject_rule:  :previous_step,
        description:     "Operations team confirms the verified KYC documents have been archived " \
                         "in the fund's document management system with the correct retention tags.")
    end

    # Condition: fires only when verified changes to true.
    t3 = WorkflowTemplate.find_by(entity: entity, name: "Post-Verification KYC Audit")
    if t3 && WorkflowAutoAssignmentRule.where(entity: entity, workflow_template: t3).none?
      WorkflowAutoAssignmentRule.create!(
        entity:            entity,
        workflow_template: t3,
        workflowable_type: "InvestorKyc",
        conditions:        [{ "attribute" => "verified", "operator" => "eq", "value" => "true" }],
        auto_launch:       true,
        priority:          0,
        created_by:        actor1
      )
      log.call("         Auto-assignment rule: verified = true")
    end

    # ── Approval templates ────────────────────────────────────────────────────

    log.call("")
    log.call("── Approval workflows ────────────────────────────────────")

    create_template.call(
      "Investment Committee Vote",
      workflowable_type:        "Approval",
      description:              "Pre-IC screening followed by a unanimous IC vote. " \
                                "Used for investment approvals requiring formal committee sign-off.",
      reminder_interval_days:   2,
      attach_document_in_email: false
    ) do |t|
      add_step.call(t, 1, "Pre-IC Screening", [actor1],
        states:          "Ready for IC,Needs Revision,Rejected",
        quorum_rule:     :any_one,
        on_reject_rule:  :stop,
        description:     "Associate reviews the proposal and confirms it is ready to be presented to the IC.")
      add_step.call(t, 2, "IC Vote", [actor1, actor2].uniq(&:id),
        states:          "Approved,Rejected,Abstain",
        quorum_rule:     :all,
        on_reject_rule:  :previous_step,
        description:     "All IC members must vote. A rejection sends the proposal back for revision.")
    end

    create_template.call(
      "Legal & Compliance Clearance",
      workflowable_type:        "Approval",
      description:              "Sequential clearance from legal then compliance. " \
                                "Used for approvals that require both teams to sign off independently.",
      reminder_interval_days:   3,
      attach_document_in_email: false
    ) do |t|
      add_step.call(t, 1, "Legal Review", [actor1],
        states:          "Cleared,Amendments Required,Rejected",
        quorum_rule:     :any_one,
        on_reject_rule:  :stop,
        description:     "Legal counsel reviews the approval for contractual and regulatory correctness.")
      add_step.call(t, 2, "Compliance Sign-off", [actor2],
        states:          "Approved,Rejected",
        quorum_rule:     :any_one,
        on_reject_rule:  :stop,
        description:     "Compliance officer confirms no policy or regulatory breach before the approval is actioned.")
    end

    # ── Summary ───────────────────────────────────────────────────────────────
    log.call("")
    log.call("=" * 60)
    log.call("Seed complete for entity: #{entity.name}")
    log.call("  Created : #{created}")
    log.call("  Skipped : #{skipped} (already existed)")
    log.call("=" * 60)

  rescue StandardError => e
    puts e.message
    puts e.backtrace.first(10).join("\n")
    raise e
  end

  # ── Teardown ────────────────────────────────────────────────────────────────

  SEEDED_TEMPLATE_NAMES = [
    "LP Data Room Review",
    "Regulatory Filing Review",
    "KYC Onboarding Kick-off",
    "KYC Submission Review",
    "Post-Verification KYC Audit",
    "Investment Committee Vote",
    "Legal & Compliance Clearance"
  ].freeze

  desc <<~DESC
    Remove all seeded workflow templates for ENTITY_ID (idempotent).

    Usage:
      rake 'workflow_seeds:teardown[ENTITY_ID]'

    Archives any active instances before destroying each template.
  DESC
  task :teardown, [:entity_id] => :environment do |_, args|
    entity_id = args[:entity_id].to_i
    abort "Usage: rake 'workflow_seeds:teardown[ENTITY_ID]'" if entity_id.zero?

    entity = Entity.find_by(id: entity_id) || abort("Entity #{entity_id} not found")
    log    = ->(msg) { puts "[workflow_seeds] #{msg}" }

    names = SEEDED_TEMPLATE_NAMES

    names.each do |name|
      template = WorkflowTemplate.find_by(entity: entity, name: name)
      unless template
        log.call("SKIP  '#{name}' — not found")
        next
      end

      # Archive active instances so dependent records don't block destroy
      WorkflowInstance.where(entity_id: entity.id, workflow_template: template)
                      .instance_active
                      .each do |inst|
        inst.instance_archived!
        log.call("  Archived WorkflowInstance##{inst.id}")
      end

      template.destroy!
      log.call("DESTROY '#{name}'")
    end

    log.call("Teardown complete.")
  rescue StandardError => e
    puts e.message
    puts e.backtrace.first(10).join("\n")
    raise e
  end
end
