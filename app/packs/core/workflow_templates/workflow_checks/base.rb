# A check answers one question about a workflowable record's data, e.g. "is every call notice
# approved?". It only reads: it never writes, sends email, looks at other steps, or knows where
# the workflow is. The evaluator decides what the answer means.
#
# Subclasses declare their key, a label for the step editor, and the workflowable type they apply
# to (nil = any type), then implement #call(record) returning a WorkflowChecks::Result.
module WorkflowChecks
  class Base
    class_attribute :key, :label, :workflowable_type, instance_writer: false

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
