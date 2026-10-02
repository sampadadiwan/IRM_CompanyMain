class WorkflowTemplate < ApplicationRecord
  belongs_to :entity

  has_many :workflow_steps,              -> { order(:position) }, dependent: :destroy, inverse_of: :workflow_template
  has_many :workflow_step_actors,        through: :workflow_steps
  has_many :workflow_assignments,        dependent: :nullify
  has_many :workflow_auto_assignment_rules, dependent: :destroy

  accepts_nested_attributes_for :workflow_steps, allow_destroy: true

  # All workflowable model names that may be scoped to a template.
  # Order matters — this is the order shown in the select dropdown.
  # "Investor" covers both regular investors (onboarding) and portfolio companies
  # (KPI report review) — the two use cases are distinguished by `category` in the
  # auto-assignment rule's conditions, not by a separate workflowable_type.
  # CapitalDistribution: capital-distribution-journey (Worked examples H2 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples)
  WORKFLOWABLE_TYPE_OPTIONS = %w[Folder InvestorKyc CapitalCommitment CapitalCall CapitalDistribution Approval Investor].freeze

  # How far saved step positions are moved aside while they are being resequenced (see
  # park_step_positions) — comfortably beyond any real template's step count
  POSITION_PARK_OFFSET = 1000

  before_validation { self.workflowable_type = nil if workflowable_type.blank? }

  # Steps are ordered by the number typed into each row of the template form
  before_validation :renumber_workflow_steps
  before_save :park_step_positions

  validates :name, presence: true
  validates :name, uniqueness: { scope: :entity_id, message: "must be unique within your organisation" }
  validates :workflowable_type, inclusion: { in: WORKFLOWABLE_TYPE_OPTIONS, message: "is not a valid workflowable type" },
                                allow_nil: true, allow_blank: true

  # workflowable_type is immutable once set — changing it would orphan existing assignments
  validate :workflowable_type_immutable, on: :update

  def to_s
    name
  end

  # A copy of this template with the same steps (kind, checks, skips, owners, approvers, settings) and
  # no rules, named "Copy of <name>" (numbered if taken). The copy has no system_key, so journey setup
  # never treats it as the seeded template. Used to give one KYC form type its own journey.
  # Worked examples E25, E26 — openspec/changes/investor-kyc-journey/design.md#worked-examples
  def duplicate!
    copy = nil
    transaction do
      copy = WorkflowTemplate.create!(attributes.except("id", "name", "system_key", "created_at", "updated_at")
                                                .merge("name" => copy_name))
      # A template has a handful of steps, kept in position order (find_each would drop the order)
      workflow_steps.includes(:workflow_step_actors).each do |step| # rubocop:disable Rails/FindEach
        new_step = copy.workflow_steps.create!(step.attributes.except("id", "workflow_template_id", "created_at", "updated_at"))
        step.workflow_step_actors.each { |actor| new_step.workflow_step_actors.create!(user_id: actor.user_id) }
      end
    end
    copy
  end

  # True for a seeded journey template (e.g. capital_call_full) — templates that track a process
  # from data rather than a pure approval chain
  def journey?
    system_key.present?
  end

  # Number of objects currently assigned to this template across all workflowable types
  def active_workflowable_count
    workflow_assignments.count
  end

  # Templates scoped to a specific type (or with no type set) that match the given class name
  def self.for_workflowable_type(type_name)
    where(workflowable_type: [type_name, nil])
  end

  # Whether this template could plausibly apply to the given record. workflowable_type alone
  # is too coarse when one type covers multiple sub-audiences — e.g. "Investor" spans both
  # regular investors and portfolio companies, distinguished only by `category` in a
  # WorkflowAutoAssignmentRule's conditions, not by a column on WorkflowTemplate itself. So:
  # a template with no auto-assignment rules for this type has no known restriction (eligible);
  # a template whose rules ALL evaluate false against this exact record could never have been
  # auto-assigned to it, which is a strong signal it's scoped to a different sub-audience.
  def eligible_for?(workflowable)
    rules = workflow_auto_assignment_rules.where(workflowable_type: workflowable.workflowable_type_name)
    return true if rules.none?
    rules.any? { |rule| rule.matches?(workflowable) }
  end

  private

  # "Copy of X", or "Copy of X (2)", "(3)"… when that name is taken in the entity
  def copy_name
    base = "Copy of #{name}"
    taken = WorkflowTemplate.where(entity_id:).where("name LIKE ?", "#{WorkflowTemplate.sanitize_sql_like(base)}%").pluck(:name)
    return base unless taken.include?(base)

    (2..).each { |n| return "#{base} (#{n})" unless taken.include?("#{base} (#{n})") }
  end

  # Turn the step numbers typed into the form into a clean 1..n sequence.
  # An admin reorders by typing a new number on one row only — e.g. typing "2" on what was step 4
  # moves it up and the rest close ranks, so no other row has to be retyped. The row the admin
  # actually typed into wins a tie, so it takes the slot it asked for and pushes the incumbent
  # down; untouched rows keep their order, and a row just added (no number yet) lands last.
  def renumber_workflow_steps
    # Rows the admin deleted keep their old numbers — they are about to be destroyed anyway
    surviving = workflow_steps.reject(&:marked_for_destruction?)
    return if surviving.empty?

    ordered = surviving.each_with_index.sort_by do |step, index|
      [step.position || Float::INFINITY, step.position_changed? ? 0 : 1, index]
    end
    slots = ordered.each_with_index.map { |(step, _index), slot| [step, slot + 1] }

    # When nothing actually moves, leave the records alone so an ordinary save (a renamed template,
    # an edited step description) doesn't park and rewrite every step for no reason
    @steps_resequenced = slots.any? { |step, slot| step.new_record? || step.position_in_database != slot }
    return unless @steps_resequenced

    slots.each do |step, slot|
      step.position = slot
      # park_step_positions moves the saved rows aside, so every step has to be written back even
      # when its number is unchanged — otherwise it would be left behind in the parked range
      step.position_will_change!
    end
  end

  # Move the saved rows out of the 1..n range before autosave writes the new numbers.
  # workflow_steps has a UNIQUE index on [workflow_template_id, position] and Rails updates the
  # children one row at a time, so swapping steps 1 and 2 would otherwise collide on the first
  # write. A constant offset keeps the parked rows unique among themselves, and no real template
  # has 1000 steps, so a parked row can never collide with an unparked one either. Both the
  # parking and the rewrite run inside the save's transaction, so a failure rolls both back.
  def park_step_positions
    return unless persisted? && @steps_resequenced

    WorkflowStep.where(workflow_template_id: id)
                .update_all("position = position + #{POSITION_PARK_OFFSET}")
  end

  def workflowable_type_immutable
    return unless workflowable_type_changed? && workflowable_type_was.present?
    errors.add(:workflowable_type, "cannot be changed after it has been set")
  end
end
