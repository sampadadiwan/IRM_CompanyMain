# Skip for Approve call: imported calls are never approved in the app.
# Worked examples E3, E25 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class Imported < WorkflowChecks::Base
      include Support

      self.key = "capital_call.imported"
      self.label = "Skip: imported call"
      self.workflowable_type = "CapitalCall"

      def call(call)
        call.manual_generation ? pass(message: "Imported calls are not approved in CapHive") : fail_with(message: "Not imported")
      end
    end
  end
end
