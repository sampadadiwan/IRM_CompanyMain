# 2. Add call notice template — the fund has a "Call Template". Commitment templates only override a
# fund template of the same name, so the fund-level template is what decides (design review).
# Worked examples E5 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class AddCallNoticeTemplate < WorkflowChecks::Base
      include Support

      self.key = "capital_call.add_call_notice_template"
      self.label = "Add call notice template"
      self.workflowable_type = "CapitalCall"

      def call(call)
        templates = call.fund.documents.templates.where(owner_tag: "Call Template")
        return pass(message: "Call notice template ready", passed_since: templates.minimum(:created_at)) if templates.exists?

        fail_with(message: "The fund has no call notice template", action_label: "Open the fund", action_path: routes.fund_path(call.fund))
      end
    end
  end
end
