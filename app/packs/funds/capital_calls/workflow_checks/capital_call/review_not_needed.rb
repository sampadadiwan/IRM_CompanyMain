# Skip for the review tasks: notices don't apply, or they have already been sent — a review after
# sending can't change anything, so it must never block the journey (design Decision 15).
# Worked examples E23, E24 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class ReviewNotNeeded < WorkflowChecks::Base
      include Support

      self.key = "capital_call.review_not_needed"
      self.label = "Skip: notices not applicable or already sent"
      self.workflowable_type = "CapitalCall"

      def call(call)
        not_applicable = NoticesNotApplicable.new.call(call)
        return not_applicable if not_applicable.passed?
        return pass(message: "Notices have already been sent") if notices_all_sent?(call)

        fail_with(message: "Review needed")
      end
    end
  end
end
