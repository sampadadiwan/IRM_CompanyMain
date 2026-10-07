require_relative "support/workflow_seed_helpers"

namespace :investor_workflow_seeds do
  desc <<~DESC
    Seed the Investor-workflow scenario for a given entity:

      "Investor Onboarding" — auto-assigned + auto-launched the moment a non-portfolio-company
                              Investor is created.

    (The former "Portfolio Company KPI Report Review" scenario was removed: KPI reports now have
    their own journey — openspec/changes/kpi-report-journey, design Decision 10.)

    Usage:
      rake 'investor_workflow_seeds:seed[ENTITY_ID]'

    Idempotent: templates/rules are found-or-created by name.
  DESC
  task :seed, [:entity_id] => :environment do |_, args|
    entity_id = args[:entity_id].to_i
    abort "Usage: rake 'investor_workflow_seeds:seed[ENTITY_ID]'" if entity_id.zero?

    entity, actor1, actor2 = WorkflowSeedHelpers.load_entity_and_actors(entity_id)
    log = WorkflowSeedHelpers.logger_for("investor_workflow_seeds")

    log.call("Entity : #{entity.name} (id=#{entity_id})")
    log.call("Actor1 : #{actor1.email}")
    log.call("Actor2 : #{actor2.email}")
    log.call("")

    created = 0
    skipped = 0

    create_template = lambda do |name, attrs, &block|
      _template, was_created = WorkflowSeedHelpers.create_template(entity, name, attrs, log: log, &block)
      was_created ? created += 1 : skipped += 1
    end

    add_step = lambda do |template, pos, step_name, actors, step_attrs = {}|
      WorkflowSeedHelpers.add_step(template, pos, step_name, actors, step_attrs, log: log)
    end

    # ── Scenario 1: Investor Onboarding ───────────────────────────────────────
    #
    # category != "Portfolio Company" covers regular LPs/prospective investors — the
    # people-facing relationship, not a portfolio company being tracked for KPIs.
    # auto_launch: true because onboarding should kick off immediately, with no separate
    # business event to wait for.

    log.call("── Investor Onboarding ───────────────────────────────────")

    create_template.call(
      "Investor Onboarding",
      workflowable_type:        "Investor",
      description:              "Kicks off the moment a new (non-portfolio-company) investor " \
                                "is added. Tracks internal onboarding tasks: granting data room " \
                                "access and assigning a relationship manager.",
      reminder_interval_days:   3,
      attach_document_in_email: false
    ) do |t|
      add_step.call(t, 1, "Welcome & Data Room Access", [actor1],
        states:          "Access Granted,Pending,Declined",
        quorum_rule:     :any_one,
        on_reject_rule:  :stop,
        description:     "Send the welcome email and grant data room access to the new investor.")
      add_step.call(t, 2, "Relationship Manager Assigned", [actor2],
        states:          "Assigned,Pending",
        quorum_rule:     :any_one,
        on_reject_rule:  :previous_step,
        description:     "Confirm a relationship manager has been assigned and introduced.")
    end

    onboarding_template = WorkflowTemplate.find_by(entity: entity, name: "Investor Onboarding")
    if onboarding_template && WorkflowAutoAssignmentRule.where(entity: entity, workflow_template: onboarding_template).none?
      WorkflowAutoAssignmentRule.create!(
        entity:            entity,
        workflow_template: onboarding_template,
        workflowable_type: "Investor",
        # not_eq (rather than an explicit list of LP-style categories) so this rule keeps
        # working if the entity's configurable investor_categories list changes later.
        conditions:        [{ "attribute" => "category", "operator" => "not_eq", "value" => "Portfolio Company" }],
        auto_launch:       true,
        priority:          0,
        created_by:        actor1
      )
      log.call("         Auto-assignment rule: category != Portfolio Company (auto_launch: true)")
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

  INVESTOR_WORKFLOW_TEMPLATE_NAMES = [
    "Investor Onboarding",
    "Portfolio Company KPI Report Review"
  ].freeze

  desc <<~DESC
    Remove everything created by investor_workflow_seeds:seed for ENTITY_ID (idempotent).

    Usage:
      rake 'investor_workflow_seeds:teardown[ENTITY_ID]'

    Destroys the demo Investor/KpiReport/Kpi rows FIRST (which cascades to their own
    WorkflowInstance/WorkflowAssignment rows via Workflowable's `dependent: :destroy`),
    then archives any remaining active instances and destroys each template.

    Note: `workflow_instances.workflow_template_id` is a real DB foreign key with no
    ON DELETE cascade/nullify (see db/schema.rb), so a template can only be destroyed once
    NO WorkflowInstance row (active or archived) still references it — archiving alone does
    not remove the FK reference. If you manually created extra Investors against these
    templates (e.g. while testing auto-launch), destroy those first or this task will report
    which template it could not remove instead of raising.
  DESC
  task :teardown, [:entity_id] => :environment do |_, args|
    entity_id = args[:entity_id].to_i
    abort "Usage: rake 'investor_workflow_seeds:teardown[ENTITY_ID]'" if entity_id.zero?

    entity = Entity.find_by(id: entity_id) || abort("Entity #{entity_id} not found")
    log    = WorkflowSeedHelpers.logger_for("investor_workflow_seeds")

    # Demo data goes first: destroying the Investor cascades (via Workflowable's
    # `dependent: :destroy`) to its own WorkflowAssignment/WorkflowInstance rows, which is
    # what clears the FK reference the "Portfolio Company KPI Report Review" template needs
    # gone before it can be destroyed below.
    demo_investor = Investor.find_by(entity: entity, investor_name: "Demo Portfolio Co")
    if demo_investor
      # Investor#portfolio_kpi_reports has no `dependent: :destroy`, so KpiReport/Kpi rows
      # must be destroyed explicitly first (KpiReport itself does cascade to its Kpis).
      demo_investor.portfolio_kpi_reports.each do |kr|
        kr.destroy!
        log.call("  Destroyed demo KpiReport##{kr.id} (and its Kpi rows)")
      end
      demo_investor.destroy!
      log.call("DESTROY demo Investor 'Demo Portfolio Co'")
    else
      log.call("SKIP  demo Investor — not found")
    end

    INVESTOR_WORKFLOW_TEMPLATE_NAMES.each do |name|
      template = WorkflowTemplate.find_by(entity: entity, name: name)
      unless template
        log.call("SKIP  '#{name}' — not found")
        next
      end

      WorkflowInstance.where(entity_id: entity.id, workflow_template: template)
                      .instance_active
                      .each do |inst|
        inst.instance_archived!
        log.call("  Archived WorkflowInstance##{inst.id}")
      end

      begin
        template.destroy!
        log.call("DESTROY '#{name}'")
      rescue ActiveRecord::InvalidForeignKey
        remaining = WorkflowInstance.where(workflow_template: template).count
        log.call("SKIP  '#{name}' — #{remaining} WorkflowInstance row(s) still reference it " \
                  "(archiving doesn't remove the FK; destroy those Investors first)")
      end
    end

    log.call("Teardown complete.")
  rescue StandardError => e
    puts e.message
    puts e.backtrace.first(10).join("\n")
    raise e
  end
end
