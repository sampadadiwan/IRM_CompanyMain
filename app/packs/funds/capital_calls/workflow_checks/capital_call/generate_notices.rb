# 3. Generate notices — every notifiable remittance has a generated notice. Investors whose KYC is
# not verified never get one (the doc job skips them), so the task stays current and says so.
# Worked examples H2, E20 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class GenerateNotices < WorkflowChecks::Base
      include Support

      self.key = "capital_call.generate_notices"
      self.label = "Generate notices"
      self.workflowable_type = "CapitalCall"

      def call(call)
        notifiable = notifiable_remittances(call)
        total = notifiable.count
        notices = generated_notices(call, notifiable)
        with_notice = notices.distinct.count(:owner_id)
        missing = total - with_notice
        return pass(message: "#{with_notice} notices generated", passed_since: notices.maximum(:created_at), fresh_since: notices.minimum(:created_at)) if total.positive? && missing.zero?

        unverified = notifiable.where.not(id: notices.select(:owner_id))
                               .left_joins(capital_commitment: :investor_kyc)
                               .where("investor_kycs.id IS NULL OR investor_kycs.verified = ?", false).count
        message = if unverified.positive? && unverified == missing && with_notice.positive?
                    "#{unverified} #{'investor'.pluralize(unverified)} #{unverified == 1 ? 'has' : 'have'} unverified KYC — notices are not generated for them"
                  else
                    "#{with_notice} of #{total} notices generated"
                  end
        fail_with(message:, action_label: "Generate Documents", action_path: call_path(call), action_target: GENERATE_DOCS_BTN)
      end
    end
  end
end
