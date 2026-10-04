# A check answers one question about a workflowable record's data, e.g. "is every call notice
# approved?". It only reads: it never writes, sends email, looks at other steps, or knows where
# the workflow is. The evaluator decides what the answer means.
#
# Subclasses declare their key, a label for the step editor, and the workflowable type they apply
# to (nil = any type), then implement #call(record) returning a WorkflowChecks::Result.
module WorkflowChecks
  class Base
    class_attribute :key, :label, :workflowable_type, instance_writer: false

    # A closing check: when it passes, every earlier step not yet done (or n/a) is shown as n/a with
    # closing_note, so the journey can complete (e.g. a KYC verified before every task was done).
    # Steps already passed keep their ✓; no sign-off is cleared. Off by default.
    # Worked examples E6, E11 — openspec/changes/investor-kyc-journey/design.md#worked-examples
    class_attribute :closes_journey, instance_writer: false, default: false
    class_attribute :closing_note, instance_writer: false, default: "Done without this step"

    # The step popup's copy (JourneyHelper#journey_step_info), one sentence each:
    #   how     — what the user does to complete the step
    #   why     — why the step exists
    #   effects — what completing it changes, and whether investors are emailed (say so either way)
    # Fixed text, so it never describes live data — the popup's status and team notifications come
    # from the step itself. Only checks that decide a step need them; skip checks leave them nil.
    class_attribute :how, :why, :effects, instance_writer: false

    # Returns a WorkflowChecks::Result for the record
    def call(_record)
      raise NotImplementedError, "#{self.class.name} must implement #call(record)"
    end

    private

    # Shorthands so subclasses read naturally
    def pass(**) = WorkflowChecks::Result.pass(**)
    def fail_with(**) = WorkflowChecks::Result.fail(**)
  end
end
