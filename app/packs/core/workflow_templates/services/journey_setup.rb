# Base for seeding a record type's two journeys (Full and Light) for an entity, plus the
# auto-assignment rules that launch them on new records, and the workflow templates permission so
# admins can edit them. Each journey kind is a subclass that declares its templates as constants:
#
#   WORKFLOWABLE_TYPE  "CapitalCall"            — the record type the journeys track
#   KEY_PREFIX         "capital_call."          — prefix of every step's check_key / skip_key
#   LABEL              "capital call journeys"  — how messages and the rollout name this kind
#   FULL_KEY / LIGHT_KEY, FULL_NAME / LIGHT_NAME — system_key and name of each template
#   DESCRIPTION        the templates' description
#   FULL_STEPS         [[name, kind, check, skip, unlocks, description], ...]
#   LIGHT_STEP_NAMES   the Full steps the Light journey keeps
#   LIGHT_CONDITIONS   the rule conditions that pick Light (imported records)
#   APPROVE_STEP_NAME  the Full step the sign-off goes before ("Approve call", "Verify KYC")
#
# Optional (defaults below keep calls and distributions as they were):
#   LIGHT_KEY          nil → a single template and one catch-all rule (investor KYC)
#   ENTITY_TYPES       which entity types get this kind (default ["Investment Fund"])
#   SIGN_OFF_NAME / SIGN_OFF_DESCRIPTION   the seeded approval step (default the CFO sign-off)
#   FULL_LABEL         what messages call the Full template ("Full"; "KYC" for the single KYC journey)
#
# The Full journey includes a "CFO sign-off" approval step with NO approvers: the admin picks them
# by editing that step in the journey template. Until then it shows as n/a (WorkflowEvaluator), so
# nothing waits on it. A Full template seeded before this step existed gets it on the next setup.
#
# Idempotent: templates are found by system_key (so an admin's rename or added steps are kept),
# and no rule is created while the entity already has a rule for the type. It never launches a
# journey on an existing record — only records created afterwards get one. A template the admin has
# disabled stays disabled: setup never re-enables one behind their back, it only reports it
# (report[:disabled]) so the "Set up journeys" menu can show the kind as disabled rather than done.
#
# execute: false reports what it would do and writes nothing (rollout dry run).
#
# Shared by the capital call and capital distribution journeys so both seed the same way
# (capital-distribution-journey design Decision 4).
# Worked examples H1, H11, E14 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
# Worked examples H1, H10, E20 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
class JourneySetup < Trailblazer::Operation
  # Journey kinds that can be set up, by the key the UI and rake tasks use. Class names are
  # constantized only from this hash, never from a request parameter.
  KINDS = {
    "capital_call" => "CapitalCallJourneySetup",
    "capital_distribution" => "CapitalDistributionJourneySetup",
    "investor_kyc" => "InvestorKycJourneySetup",
    "kpi_report" => "KpiReportJourneySetup"
  }.freeze

  # The seeded approval step (a human step: approvers vote; any one approval passes it)
  CFO_STEP_NAME = "CFO sign-off".freeze
  CFO_STEP_DESCRIPTION = "The CFO signs off before approval. Pick the approver(s) by editing this step; " \
                         "until someone is picked it shows as not applicable.".freeze

  # Per-kind overrides (investor-kyc-journey design Decision 3); a subclass redefines the constant
  LIGHT_KEY = nil
  LIGHT_NAME = nil
  LIGHT_STEP_NAMES = [].freeze
  ENTITY_TYPES = ["Investment Fund"].freeze
  SIGN_OFF_NAME = CFO_STEP_NAME
  SIGN_OFF_DESCRIPTION = CFO_STEP_DESCRIPTION
  FULL_LABEL = "Full".freeze

  # Seeded tasks to add to a Full template that ALREADY exists, as
  # { anchor task name => [seeded task names, in order] }: they are inserted immediately before the
  # anchor, because find_or_seed only writes steps for a template it creates, so a kind that gains a
  # task would otherwise leave every set-up company behind. The generalisation of add_cfo_step.
  # {} (the default) means this kind never backfills.
  # Worked examples H7, E9, E10 — openspec/changes/investor-kyc-email-review-steps/design.md#worked-examples
  BACKFILL_STEPS = {}.freeze

  # Whether this kind seeds a Light template next to the Full one
  def self.light?
    self::LIGHT_KEY.present?
  end

  # Whether this kind is offered to the entity (rollout, SetupCompany, the Set up journeys menu)
  # Worked examples X4 — openspec/changes/investor-kyc-journey/design.md#worked-examples
  def self.available_for?(entity)
    entity.present? && self::ENTITY_TYPES.include?(entity.entity_type)
  end

  # Every entity type some kind is offered to
  def self.entity_types
    KINDS.keys.flat_map { |kind| for_kind(kind)::ENTITY_TYPES }.uniq
  end

  # The Set up journeys menu's confirmation for this kind, from its dry-run report
  def self.confirm_message(plan)
    records = self::RECORD.pluralize
    templates = if plan[:templates].none?
                  "no templates (they exist)"
                elsif light?
                  "the #{self::FULL_LABEL} (#{self::FULL_STEPS.size} tasks) and Light (#{self::LIGHT_STEP_NAMES.size} tasks) journey templates"
                else
                  "the #{self::FULL_NAME} journey template (#{self::FULL_STEPS.size} tasks)"
                end
    rules = if plan[:rules].none? then ""
            elsif light? then ", and rules giving imported #{records} Light and every other #{self::RECORD} Full"
            else ", and a rule giving every new #{self::RECORD} this journey"
            end
    sign_off = plan[:cfo] ? ", and a #{self::SIGN_OFF_NAME} step in the #{self::FULL_LABEL} journey" : ""
    # Seeded tasks the company's existing template predates (BACKFILL_STEPS): name them, so the
    # admin knows their journey grows two tasks rather than finding out from the step bar
    steps = if plan[:steps].blank?
              ""
            else
              ", and the #{plan[:steps].to_sentence} #{'task'.pluralize(plan[:steps].size)} in the #{self::FULL_LABEL} journey"
            end
    # A kind without a sign-off step (the KPI report journey) has no approver to warn about
    approver = self::SIGN_OFF_NAME ? "The #{self::SIGN_OFF_NAME} step has no approver: edit it to pick one (until then it is skipped). " : ""
    "This adds the standard #{self::LABEL} for this company: #{templates}#{rules}#{sign_off}#{steps}. " \
      "#{approver}Only #{records} created from now on get a journey. Anything already set up is kept."
  end

  step :plan
  step :apply

  # The setup class for a kind; raises KeyError for anything not in KINDS
  def self.for_kind(kind)
    KINDS.fetch(kind.to_s).constantize
  end

  # The rollout rake tasks' body: runs the setup for every fund entity (or ENTITY_ID) and prints
  # what was, or would be, added. One entity's failure is reported and the rest carry on.
  def self.rollout(kind, execute:, entity_id: nil, io: $stdout)
    setup = for_kind(kind)
    entities = Entity.where(entity_type: setup::ENTITY_TYPES)
    entities = entities.where(id: entity_id) if entity_id.present?

    io.puts(execute ? "Seeding #{setup::LABEL}" : "DRY RUN — nothing will be written (set EXECUTE=1 to apply)")
    failures = []

    entities.find_each do |entity|
      # A kind may narrow its entity types further (the KPI report journey: funds that use KPIs)
      next unless setup.available_for?(entity)

      # One transaction per entity inside the setup, so one failure doesn't stop the rest
      report = setup.call(entity:, execute:)[:report]
      planned = []
      planned << "templates: #{report[:templates].join(', ')}" if report[:templates].any?
      planned << "rules: #{report[:rules].join(', ')}" if report[:rules].any?
      planned << "add #{setup::SIGN_OFF_NAME} to the #{setup::FULL_LABEL} journey" if report[:cfo]
      planned << "add tasks: #{report[:steps].join(', ')}" if report[:steps].present?
      planned << "enable workflow templates" if report[:flag]
      io.puts "  #{entity.name} (id=#{entity.id}): #{planned.any? ? planned.join('; ') : 'already set up'}"
    rescue StandardError => e
      failures << "#{entity.name} (id=#{entity.id}): #{e.message}"
      io.puts "  #{entity.name} (id=#{entity.id}): FAILED — #{e.message}"
    end

    io.puts(failures.any? ? "Done with #{failures.size} failure(s):\n  #{failures.join("\n  ")}" : "Done.")
  end

  # Works out what is missing for this entity
  def plan(ctx, entity:, **)
    keys = [self.class::FULL_KEY, self.class::LIGHT_KEY].compact
    templates = WorkflowTemplate.where(entity:, system_key: keys).index_by(&:system_key)
    ctx[:report] = {
      entity: entity.name,
      templates: keys.reject { |key| templates.key?(key) },
      # The admin may have set up their own rules: never add ours next to them
      rules: if WorkflowAutoAssignmentRule.exists?(entity:, workflowable_type: self.class::WORKFLOWABLE_TYPE)
               []
             else
               self.class.light? ? %w[imported_to_light all_to_full] : %w[all_to_full]
             end,
      flag: !entity.permissions.enable_workflow_templates?,
      # A Full template seeded before the CFO sign-off step existed (a new template gets it seeded)
      # A kind with no sign-off step at all (SIGN_OFF_NAME nil — the KPI report journey) never gets one added
      # Worked examples E1 — openspec/changes/kpi-report-journey/design.md#worked-examples
      cfo: self.class::SIGN_OFF_NAME.present? && templates[self.class::FULL_KEY].present? &&
           !templates[self.class::FULL_KEY].workflow_steps.exists?(name: self.class::SIGN_OFF_NAME),
      # Seeded tasks an existing Full template predates, in BACKFILL_STEPS order. [] for a template
      # about to be seeded whole, for a kind that declares no backfill, and once they are all there.
      steps: missing_backfill_steps(templates[self.class::FULL_KEY]),
      # Seeded templates the admin has since disabled. Setup leaves them disabled — re-enabling is
      # the admin's call — but the menu has to say so, otherwise a kind whose templates are all off
      # reads as "set up" while new records quietly get no journey.
      disabled: templates.values.reject(&:enabled).map(&:name)
    }
    true
  end

  # Writes what plan found missing, in one transaction (skipped on a dry run)
  def apply(ctx, entity:, execute: true, **)
    return true unless execute

    report = ctx[:report]
    setup = self.class
    ActiveRecord::Base.transaction do
      full = find_or_seed(entity, setup::FULL_KEY, setup::FULL_NAME, setup::FULL_STEPS)
      add_cfo_step(full) if report[:cfo]
      insert_missing_steps(full, report[:steps]) if report[:steps].present?
      if setup.light?
        light = find_or_seed(entity, setup::LIGHT_KEY, setup::LIGHT_NAME,
                             setup::FULL_STEPS.select { |row| setup::LIGHT_STEP_NAMES.include?(row[0]) })
      end
      if report[:rules].any?
        # Imported records → Light (checked first), everything else → Full. A kind with no Light
        # (investor KYC) gets only the catch-all, so it is the default an admin's form-type rule overrides.
        if light
          WorkflowAutoAssignmentRule.create!(entity:, workflow_template: light, workflowable_type: setup::WORKFLOWABLE_TYPE,
                                             priority: 10, auto_launch: true, conditions: setup::LIGHT_CONDITIONS)
        end
        WorkflowAutoAssignmentRule.create!(entity:, workflow_template: full, workflowable_type: setup::WORKFLOWABLE_TYPE,
                                           priority: 100, auto_launch: true, conditions: [])
      end
      if report[:flag]
        entity.permissions.set(:enable_workflow_templates)
        entity.save!(validate: false)
      end
    end
    true
  end

  private

  # The existing template by system_key (whatever the admin has done to it), or a new one with
  # the seeded steps
  def find_or_seed(entity, system_key, name, rows)
    existing = WorkflowTemplate.find_by(entity:, system_key:)
    return existing if existing

    setup = self.class
    template = WorkflowTemplate.create!(
      entity:, system_key:, name:, workflowable_type: setup::WORKFLOWABLE_TYPE, reminder_interval_days: 2,
      description: setup::DESCRIPTION
    )
    rows.each_with_index { |row, idx| create_step(template, row, idx + 1) }
    template
  end

  # One step from a FULL_STEPS row at the given position. Shared by seeding and by the backfill, so
  # a task added to an existing template is identical to the same task on a freshly seeded one.
  def create_step(template, row, position)
    step_name, kind, check, skip, unlocks, description = row
    # A "human" row is the sign-off: approvers, states and reject rule come from create_cfo_step
    return create_cfo_step(template, position) if kind == "human"

    setup = self.class
    template.workflow_steps.create!(
      position:, name: step_name, kind:, description:, unlocks:,
      check_key: "#{setup::KEY_PREFIX}#{check}", skip_key: skip && "#{setup::KEY_PREFIX}#{skip}",
      states: kind == "acknowledge" ? WorkflowStep::ACKNOWLEDGE_STATES : WorkflowStep::SYSTEM_STATES
    )
  end

  # The CFO sign-off: no approvers yet (picked on the template), any one approval passes, a rejection
  # sends the journey back a step
  def create_cfo_step(template, position)
    template.workflow_steps.create!(position:, name: self.class::SIGN_OFF_NAME, kind: "human", description: self.class::SIGN_OFF_DESCRIPTION,
                                    states: "Approved,Rejected", quorum_rule: "any_one", on_reject_rule: "previous_step")
  end

  # Inserts the CFO sign-off into an existing Full template, before its Approve step (or last when the
  # admin removed it). Positions are shifted from the bottom up so the unique position index never collides.
  # Worked examples E25 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def add_cfo_step(template)
    steps = template.workflow_steps
    target = steps.find_by(name: self.class::APPROVE_STEP_NAME)&.position || (steps.maximum(:position).to_i + 1)
    shift_positions_from(template, target)
    create_cfo_step(template, target)
  end

  # Makes room at `position` by moving that step and everything after it down by `by`. Bottom-up, so
  # the unique (workflow_template_id, position) index never collides part-way through the renumber.
  def shift_positions_from(template, position, by = 1)
    template.workflow_steps.where(position: position..).reorder(position: :desc)
            .each { |step| step.update!(position: step.position + by) }
  end

  # The seeded tasks in BACKFILL_STEPS this existing template does not have yet. Nothing for a
  # template that is about to be seeded whole (nil), and nothing for an anchor the admin has removed:
  # a template with no "Send KYC form" never emails the investor, so a review of that email is noise.
  def missing_backfill_steps(template)
    setup = self.class
    return [] if template.nil? || setup::BACKFILL_STEPS.empty?

    # Two narrow columns, so a 20-step template costs one small query
    rows = template.workflow_steps.pluck(:name, :check_key)
    names = rows.map(&:first)
    keys = rows.map(&:last)

    setup::BACKFILL_STEPS.flat_map do |anchor_name, step_names|
      next [] unless step_present?(anchor_name, names, keys)

      step_names.reject { |step_name| step_present?(step_name, names, keys) }
    end
  end

  # Inserts the given seeded tasks before their anchor, in BACKFILL_STEPS order
  def insert_missing_steps(template, step_names)
    self.class::BACKFILL_STEPS.each do |anchor_name, candidates|
      rows = candidates.filter_map { |name| seeded_row(name) if step_names.include?(name) }
      next if rows.empty?

      # The anchor was there when plan ran; re-read its position now, after any CFO shift
      target = step_position(template, anchor_name)
      next unless target

      shift_positions_from(template, target, rows.size)
      rows.each_with_index { |row, idx| create_step(template, row, target + idx) }
    end
  end

  # A seeded task counts as present under its seeded name OR its check key, so a template whose
  # admin renamed the task does not collect a duplicate
  def step_present?(step_name, names, keys)
    return true if names.include?(step_name)

    key = seeded_check_key(step_name)
    key.present? && keys.include?(key)
  end

  # The position of a seeded task on this template, by name or by its check key; nil when it is gone
  def step_position(template, step_name)
    steps = template.workflow_steps
    by_name = steps.find_by(name: step_name)
    return by_name.position if by_name

    key = seeded_check_key(step_name)
    key && steps.find_by(check_key: key)&.position
  end

  def seeded_row(step_name)
    self.class::FULL_STEPS.find { |row| row[0] == step_name }
  end

  # The check key seeding gives this task, or nil for a task with no check (the sign-off)
  def seeded_check_key(step_name)
    check = seeded_row(step_name)&.at(2)
    check && "#{self.class::KEY_PREFIX}#{check}"
  end
end
