require_relative "support/workflow_seed_helpers"

namespace :investor_workflow_seeds do
  desc <<~DESC
    Seed two Investor-workflow scenarios for a given entity:

      1. "Investor Onboarding"                — auto-assigned + auto-launched the moment
                                                  a non-portfolio-company Investor is created.
      2. "Portfolio Company KPI Report Review" — auto-assigned (but NOT auto-launched) the
                                                  moment a Portfolio Company Investor is created.
                                                  A new instance is only launched later, each
                                                  time a KPI report's KPIs are imported for it
                                                  (see KpiReport#launch_portfolio_company_workflow).

    Also creates one demo Portfolio Company Investor + one demo KpiReport with a few Kpi rows,
    so scenario 2 is immediately observable: launch_portfolio_company_workflow is called
    directly on the demo report (a real file upload isn't practical from a rake task), which
    exercises the exact same code path the ImportKpiWorkbookJob hook uses in production.

    Usage:
      rake 'investor_workflow_seeds:seed[ENTITY_ID]'

    Idempotent: templates/rules are found-or-created by name; the demo Investor/KpiReport are
    found-or-created by a fixed name so re-running never creates duplicates. Re-running does
    re-attempt the demo launch — WorkflowInstanceLaunch itself refuses to start a second
    active instance, so this is a harmless no-op (logged) once one is already running.
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

    # ── Scenario 2: Portfolio Company KPI Report Review ───────────────────────
    #
    # category == "Portfolio Company" scopes this to portco records only.
    # auto_launch: false is deliberate: assigning the template here only decides WHICH
    # workflow applies to this portfolio company. The actual review instance is launched
    # later, explicitly, once per KPI upload — see KpiReport#launch_portfolio_company_workflow
    # and its call site in ImportKpiWorkbookJob. The auto-assignment engine only ever fires
    # once per record (see Workflowable#apply_workflow_auto_assignment_on_update), so it
    # cannot be the thing that re-launches a review on every subsequent upload.

    log.call("")
    log.call("── Portfolio Company KPI Report Review ──────────────────")

    create_template.call(
      "Portfolio Company KPI Report Review",
      workflowable_type:        "Investor",
      description:              "Assigned automatically to every Portfolio Company. A new " \
                                "review instance is launched each time that portfolio " \
                                "company's KPI report finishes importing.",
      reminder_interval_days:   2,
      attach_document_in_email: false
    ) do |t|
      add_step.call(t, 1, "Data Accuracy Check", [actor1],
        states:          "Accurate,Needs Correction,Rejected",
        quorum_rule:     :any_one,
        on_reject_rule:  :stop,
        description:     "Spot-check the newly imported KPI figures against the source workbook.")
      add_step.call(t, 2, "Analyst Sign-off", [actor2],
        states:          "Approved,Rejected",
        quorum_rule:     :any_one,
        on_reject_rule:  :previous_step,
        description:     "Analyst confirms the KPI figures are ready to be shared/reported on.")
    end

    kpi_review_template = WorkflowTemplate.find_by(entity: entity, name: "Portfolio Company KPI Report Review")
    if kpi_review_template && WorkflowAutoAssignmentRule.where(entity: entity, workflow_template: kpi_review_template).none?
      WorkflowAutoAssignmentRule.create!(
        entity:            entity,
        workflow_template: kpi_review_template,
        workflowable_type: "Investor",
        conditions:        [{ "attribute" => "category", "operator" => "eq", "value" => "Portfolio Company" }],
        auto_launch:       false, # see comment above — launch happens on KPI upload, not here
        priority:          0,
        created_by:        actor1
      )
      log.call("         Auto-assignment rule: category == Portfolio Company (auto_launch: false)")
    end

    # ── Demo data: make scenario 2 concretely observable ──────────────────────

    log.call("")
    log.call("── Demo portfolio company + KPI upload ───────────────────")

    demo_investor = Investor.find_or_create_by!(entity: entity, investor_name: "Demo Portfolio Co") do |inv|
      inv.category      = "Portfolio Company"
      inv.primary_email = "demo.portfolio.co+#{entity.id}@example.com"
    end
    log.call("Investor: #{demo_investor.investor_name} (id=#{demo_investor.id}) — " \
             "workflow_assignment: #{demo_investor.workflow_assignment&.workflow_template&.name || 'none'}")

    demo_report = KpiReport.find_or_create_by!(
      entity:            entity,
      portfolio_company: demo_investor,
      period:            "Month",
      tag_list:          "Actual",
      as_of:             Date.current.beginning_of_month
    ) do |kr|
      kr.user = actor1
    end

    # A handful of representative KPIs — enough for kpis.none? (in
    # launch_portfolio_company_workflow) to be false.
    { "Revenue" => 250_000, "EBITDA" => 40_000, "Headcount" => 32 }.each do |kpi_name, kpi_value|
      demo_report.kpis.find_or_create_by!(name: kpi_name) do |kpi|
        kpi.entity            = entity
        kpi.portfolio_company = demo_investor
        kpi.value             = kpi_value
      end
    end
    log.call("KpiReport: #{demo_report.name} (id=#{demo_report.id}) — #{demo_report.kpis.count} KPIs")

    # Same call ImportKpiWorkbookJob makes in production once a real workbook finishes
    # importing — simulated directly here since there's no file to upload from a rake task.
    demo_report.launch_portfolio_company_workflow(actor1)
    launched = demo_investor.workflow_instances.order(created_at: :desc).first
    log.call("WorkflowInstance: #{launched ? "##{launched.id} (#{launched.status})" : 'none launched'}")

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
