module Workflowable
  extend ActiveSupport::Concern

  included do
    has_one  :workflow_assignment, as: :workflowable, dependent: :destroy
    has_many :workflow_instances,  as: :workflowable, dependent: :destroy

    # After every new record is persisted, check whether any auto-assignment rule matches.
    # Runs in an after_create so the object has a real id before rules are evaluated.
    after_create :apply_workflow_auto_assignment

    # Re-evaluate rules when any tracked attribute changes on an existing record.
    # Only fires the service when the object doesn't already have a template assigned,
    # preventing repeated re-assignment after the first match.
    after_update :apply_workflow_auto_assignment_on_update

    # Set by has_journey: the record type shows a journey panel on its page
    class_attribute :journey_panel, instance_writer: false, default: false

    # Set by workflow_rule_fields: what an auto-assignment rule may test beyond list search.
    # extra    — columns rules need that search does not expose (e.g. form_type_id)
    # excluded — searchable fields a rule should not offer (identifiers, unbounded references)
    # form_type_names — FormType names whose custom fields apply (nil = the base class name)
    class_attribute :workflow_rule_extra, instance_writer: false, default: []
    class_attribute :workflow_rule_excluded, instance_writer: false, default: []
    class_attribute :workflow_rule_form_type_names_override, instance_writer: false, default: nil

    # Ransack asks the model for its allowlist with the search's auth object. A rule's search
    # (WorkflowRuleMatcher) passes :workflow_rule, and gets the extras on top of the normal list;
    # list pages never pass it, so nothing new becomes searchable there.
    # Worked examples H1, H4, E7 — openspec/changes/workflow-rule-condition-builder/design.md#worked-examples
    singleton_class.prepend(WorkflowRuleRansack)
  end

  # Prepended onto the model's singleton class so it wraps the model's own ransackable_attributes,
  # whichever order the two are defined in
  module WorkflowRuleRansack
    # Ransacker names that read custom fields out of json_fields (see WithCustomField)
    JSON_RANSACKERS = %w[json_fields json_field_number].freeze

    def ransackable_attributes(auth_object = nil)
      base = super
      return base unless auth_object == :workflow_rule

      # Custom-field ransackers only exist on models with custom fields
      json = include?(WithCustomField) ? JSON_RANSACKERS : []
      (base + workflow_rule_extra + json).uniq
    end
  end

  # Shared by every record type with a journey (capital calls, capital distributions), so a new type
  # needs only its checks, setup table, hooks and button ids (capital-distribution-journey DRY-up).
  # Worked examples E16, E18, E19 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  class_methods do
    # Declares that this type shows a journey panel (<plural>/_journey on its page, reloaded from
    # GET /<plural>/:id/journey): open pages update in real time, and a step with no owner reminds
    # the record's creator.
    def has_journey
      self.journey_panel = true
    end

    # Declares what auto-assignment rules may test on this type, on top of its ransackable_attributes
    # and its forms' custom fields (WorkflowRuleFields builds the list from these).
    # Worked examples H1, E1 — openspec/changes/workflow-rule-condition-builder/design.md#worked-examples
    def workflow_rule_fields(extra: [], except: [], form_type_names: nil)
      self.workflow_rule_extra = extra.map(&:to_s).freeze
      self.workflow_rule_excluded = except.map(&:to_s).freeze
      self.workflow_rule_form_type_names_override = form_type_names&.map(&:to_s)&.freeze
    end

    # The FormType names whose custom fields a rule on this type may use: declared, or the base
    # class name (KYCs declare all three of their STI names)
    def workflow_rule_form_type_names
      workflow_rule_form_type_names_override || [base_class.name]
    end

    # journey_progress! for many records at once (bulk jobs, imports, document approvals), touching
    # only records that have a journey — every other one, including all records created before the
    # rollout, is skipped in SQL. ids may be an array or a select-relation.
    def journey_progress_for(ids, actor: nil)
      with_journey = WorkflowInstance.evaluated.where(workflowable_type: base_class.name).where.not(status: :archived)
      where(id: ids).where(id: with_journey.select(:workflowable_id)).find_each { |record| record.journey_progress!(actor:) }
    end
  end

  # The template currently assigned to this object, resolved through WorkflowAssignment.
  def workflow_template
    workflow_assignment&.workflow_template
  end

  # The type workflow templates, rules and instances are stored under: the STI base class, so an
  # IndividualKyc / NonIndividualKyc is matched as "InvestorKyc" (what polymorphic workflowable_type
  # already stores). For every non-STI type this is just the class name.
  # Worked examples E25 — openspec/changes/investor-kyc-journey/design.md#worked-examples
  def workflowable_type_name
    self.class.base_class.name
  end

  # Human-readable name shown in emails and the instance page.
  # Defaults to to_s — override only if the model's to_s is not user-friendly.
  def workflow_display_name
    to_s
  end

  # URL to the object shown in emails and the instance page.
  # Defaults to the conventional Rails path helper derived from the class name
  # (e.g. InvestorKyc → investor_kyc_path(self), CapitalCommitment → capital_commitment_path(self)).
  # Override only for models with non-standard routes (e.g. STI subclasses, scoped routes).
  def workflow_url(routes = Rails.application.routes.url_helpers)
    helper = :"#{self.class.name.underscore}_path"
    routes.public_send(helper, self)
  rescue NoMethodError
    raise NotImplementedError,
          "#{self.class.name} has no standard route helper '#{self.class.name.underscore}_path'. " \
          "Implement #workflow_url explicitly."
  end

  # Files to attach to step-activation emails when attach_document_in_email is true.
  # Returns [] by default — override in models that have associated files.
  def workflow_attachable_files
    []
  end

  # The most recent non-archived instance for this object, or nil if none exists
  # (never launched, or every instance so far has been archived/reset). Memoized —
  # workflow_gated?, workflow_gated_button_labels, and workflow_gate_status_label
  # are all typically called together on the same request-scoped object.
  def current_workflow_instance
    return @current_workflow_instance if defined?(@current_workflow_instance)

    @current_workflow_instance = workflow_instances.where.not(status: :archived).order(created_at: :desc).first
  end

  # True while a workflow is blocking gated actions on this object: opt-in — an object
  # that has never had a workflow launched against it is never gated. Both an in-progress
  # (active) and a failed (rejected) instance keep the gate closed; only a completed
  # instance opens it.
  def workflow_gated?
    instance = current_workflow_instance
    # Journeys (evaluated instances) only warn in this release; they never disable buttons
    return false if instance&.evaluated

    instance.present? && !instance.instance_complete?
  end

  # Worked examples E2, H12 (advisory gate) — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  # ── Journeys (evaluated workflows) ────────────────────────────────────────────────

  # True when the step that lists `label` in its unlocks is done or not applicable, or when no
  # step lists it. Uses the last evaluation stored on the instance.
  def workflow_step_unlocked?(label)
    instance = current_workflow_instance
    return true unless instance&.evaluated

    step = instance.snapshot_steps.find { |s| s[:unlocks].to_s.split(",").map(&:strip).include?(label) }
    return true unless step

    instance.step_result(step[:position])&.dig("status").in?(%w[passed na])
  end

  # Who is reminded about a stalled system/acknowledge step when the step names no owner: for a
  # type with a journey panel, the user who created the record (from the audit trail); otherwise
  # nobody. Records may override it.
  def workflow_default_owner
    # Memoized (nil included): the flow diagram asks once per journey step of the same record
    return @workflow_default_owner if defined?(@workflow_default_owner)
    return @workflow_default_owner = nil unless journey_panel && respond_to?(:audits)

    @workflow_default_owner = audits.where(action: "create").order(:created_at).first&.user
  end

  # Owners that beat the step's named owner/actors for THIS record (e.g. a KPI report's portfolio
  # company manager). [] — the default — means the step's own owner applies, as before.
  # Worked examples H7, X3 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def workflow_override_owners
    []
  end

  # Who is reminded when neither an override nor the step names anyone. Defaults to the single
  # creator, so journeys that don't override this behave exactly as before; a type may return
  # several people (a KPI report: every employee tagged Kpi).
  # Worked examples E8, E17 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def workflow_default_owners
    [workflow_default_owner].compact
  end

  # Wraps an undoing action (Unapprove, a figures edit, Recompute…). The start time is taken before
  # the action changes anything, so every sign-off given before it is reset even if a page view or
  # tick records the move back first (design Decision 11). An evaluation failure is reported but
  # never fails the action itself.
  # Worked examples E10, E10c — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  def journey_undo(note:, actor: nil)
    started_at = Time.current
    result = yield
    journey_undo_evaluate(note:, actor:, started_at:)
    result
  end

  # The evaluation half of journey_undo, for undoing actions that can't wrap themselves in a block
  # (Trailblazer operations, jobs): they capture started_at before changing anything and call this
  # after. Never raises — an evaluation failure is reported and the action stands.
  def journey_undo_evaluate(note:, started_at:, actor: nil)
    WorkflowEvaluator.for(self, cause: :undo, actor:, note:, undo_started_at: started_at)
  rescue StandardError => e
    Rails.logger.error("[journey_undo] #{self.class.name}##{id} #{note}: #{e.class}: #{e.message}")
    ErrorReport.notify(e, source: "Workflowable#journey_undo_evaluate", record: "#{self.class.name}##{id}", entity_id: try(:entity_id), note:)
    nil
  end

  # Marks journey steps stale (WorkflowStepInvalidate) from an action's hook. Never raises: a failure
  # is reported and the action that called it stands, like journey_undo_evaluate.
  # Worked examples E8, E9 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  # only_if_passed / only_if_not_passed: see WorkflowStepInvalidate (e.g. a KYC document changed only
  # moves "Validate documents" back once that step had passed — investor-kyc-journey E13).
  def journey_invalidate(check_keys:, reason:, actor: nil, **guards)
    WorkflowStepInvalidate.call(record: self, check_keys:, actor:, reason:, **guards.slice(:only_if_passed, :only_if_not_passed))
  rescue StandardError => e
    Rails.logger.error("[journey_invalidate] #{self.class.name}##{id}: #{e.class}: #{e.message}")
    ErrorReport.notify(e, source: "Workflowable#journey_invalidate", record: "#{self.class.name}##{id}", entity_id: try(:entity_id), check_keys:)
    nil
  end

  # Re-checks this record's journey after work that moves it FORWARD (a job finishing, an approval,
  # a payment), so open pages update in real time instead of waiting for the 15-minute tick.
  # A no-op for records without a journey, and never raises — the action that called it stands.
  def journey_progress!(actor: nil)
    WorkflowEvaluator.for(self, cause: :progress, actor:)
  rescue StandardError => e
    Rails.logger.error("[journey_progress!] #{self.class.name}##{id}: #{e.class}: #{e.message}")
    ErrorReport.notify(e, source: "Workflowable#journey_progress!", record: "#{self.class.name}##{id}", entity_id: try(:entity_id))
    nil
  end

  # Turbo frame id of this record's journey panel, e.g. "capital_call_journey"
  def journey_frame_id
    "#{workflowable_type_name.underscore}_journey"
  end

  # Called by WorkflowEvaluator after an evaluation changed this record's journey. Replaces the panel
  # on every open page with an empty frame that loads GET /<plural>/:id/journey, so each browser
  # re-fetches it as its own user (the panel depends on the viewer's rights, so rendered HTML can't be
  # broadcast to everyone). Sent through ActionCable (Redis adapter), so it also works from Sidekiq.
  # A no-op for types without a journey panel.
  # Worked examples J2.2 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  # Worked examples E16, E17 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def broadcast_journey_change
    return unless journey_panel

    # Built from the base class so STI records (IndividualKyc) use the base route (/investor_kycs/:id/journey)
    src = Rails.application.routes.url_helpers.polymorphic_path(becomes(self.class.base_class), action: :journey)
    frame = %(<turbo-frame id="#{journey_frame_id}" src="#{src}"></turbo-frame>)
    Turbo::StreamsChannel.broadcast_replace_to(self, :journey, target: journey_frame_id, html: frame)
  end

  # Drops the memoized current_workflow_instance so the next read sees an evaluation that just ran
  # (the call page's before_action loads it before the evaluator updates step_results)
  def forget_current_workflow_instance!
    remove_instance_variable(:@current_workflow_instance) if instance_variable_defined?(:@current_workflow_instance)
  end

  # Button labels (from the current instance's live template, not the frozen snapshot)
  # that should be disabled while workflow_gated? is true. Empty when not gated or when
  # the template sets no labels.
  def workflow_gated_button_labels
    return [] unless workflow_gated?

    current_workflow_instance.workflow_template&.gated_button_labels.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  # "Incomplete" (still active) or "Failed" (rejected) — nil when not gated.
  def workflow_gate_status_label
    instance = current_workflow_instance
    return nil unless instance

    return "Incomplete" if instance.instance_active?
    return "Failed" if instance.instance_rejected?

    nil
  end

  private

  # Called after_create to apply any matching auto-assignment rule.
  # Silently a no-op when no rules exist, already has a template, or the entity
  # does not respond to `entity` (e.g. test stubs without an association).
  def apply_workflow_auto_assignment
    return unless respond_to?(:entity) && entity.present?
    WorkflowAutoAssignmentService.call(workflowable: self)
  rescue StandardError => e
    Rails.logger.warn("[Workflowable#apply_workflow_auto_assignment] #{self.class.name}##{id}: #{e.message}")
  end

  # Called after_update to re-evaluate rules when the record changes.
  # Guards: skip if no rules could possibly match (no rules for this type+entity),
  # or if a template is already assigned (nothing left to auto-assign).
  def apply_workflow_auto_assignment_on_update
    return unless respond_to?(:entity) && entity.present?
    return if workflow_assignment.present?
    return unless WorkflowAutoAssignmentRule.where(entity: entity, workflowable_type: workflowable_type_name).exists?
    WorkflowAutoAssignmentService.call(workflowable: self)
  rescue StandardError => e
    Rails.logger.warn("[Workflowable#apply_workflow_auto_assignment_on_update] #{self.class.name}##{id}: #{e.message}")
  end
end
