# 2. Generate notices — every emailable payment has a generated notice. Investors whose KYC is not
# verified never get one (the doc job skips them), so the task stays current and says so.
# fresh_since is the oldest notice: after Recompute Fees or a figures edit invalidates this task,
# only notices generated afterwards satisfy it (design Decision 11).
# Worked examples H2, E5, E8, E11 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    class GenerateNotices < WorkflowChecks::Base
      include Support

      self.key = "capital_distribution.generate_notices"
      self.label = "Generate notices"
      self.workflowable_type = "CapitalDistribution"

      def call(dist)
        emailable = emailable_payments(dist)
        total = emailable.count
        notices = generated_notices(dist, emailable)
        with_notice = notices.distinct.count(:owner_id)
        missing = total - with_notice
        if total.positive? && missing.zero?
          return pass(message: "#{with_notice} #{'notice'.pluralize(with_notice)} generated", passed_since: notices.maximum(:created_at),
                      fresh_since: notices.minimum(:created_at))
        end

        unverified = emailable.where.not(id: notices.select(:owner_id))
                              .left_joins(capital_commitment: :investor_kyc)
                              .where("investor_kycs.id IS NULL OR investor_kycs.verified = ?", false).count
        message = if unverified.positive? && unverified == missing && with_notice.positive?
                    "#{unverified} #{'investor'.pluralize(unverified)} #{unverified == 1 ? 'has' : 'have'} unverified KYC — notices are not generated for them"
                  else
                    "#{with_notice} of #{total} notices generated"
                  end
        fail_with(message:, action_label: "Generate Documents", action_path: distribution_path(dist), action_target: GENERATE_DOCS_BTN)
      end
    end
  end
end
