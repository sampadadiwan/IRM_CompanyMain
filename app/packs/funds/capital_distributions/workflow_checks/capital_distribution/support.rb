# Shared helpers for the capital distribution journey checks. Everything here reads; nothing writes.
#
# "Emailable" payments are those whose commitment is not set to Skip Doc Gen — the same rule
# CapitalDistributionPayment#send_notification and the notice generator use. skip_doc_gen lives in
# capital_commitments.json_fields, so it is filtered in Ruby over two narrow columns
# (CapitalCommitment.skip_doc_gen_ids), as the capital call checks do.
#
# Every helper returns a relation the callers count or probe with exists?, or selects ids only —
# nothing loads payment or document rows (CLAUDE.md large-table rules).
# Inside this module ::CapitalDistribution is the model; bare CapitalDistribution is the namespace.
# Worked examples H2, E1, E2, E3 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalDistribution
    module Support
      # Controls on the distribution's OWN page (capital_distributions/show.html.erb, _details.html.erb).
      # A step whose work is done by one of these sets it as its action_target, so the journey panel
      # clicks that control instead of linking to the page the user is on. "#..." is a tab to open.
      # Keep in step with those views; a missing target falls back to action_path.
      # Worked examples H3, H5 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
      APPROVE_BTN = "capital_distribution_approve_btn".freeze
      GENERATE_DOCS_BTN = "capital_distribution_generate_docs_btn".freeze
      PAYMENTS_COMPLETED_BTN = "capital_distribution_payments_completed_btn".freeze
      NOTIFY_BTN = "capital_distribution_notify_btn".freeze
      REDEEM_UNITS_BTN = "capital_distribution_redeem_units_btn".freeze
      # The Actions menu's "View Generated Notices To Approve" link (opens in a new window)
      VIEW_NOTICES_TO_APPROVE_BTN = "capital_distribution_view_notices_to_approve_btn".freeze
      PAYMENTS_TAB = "#payments-tab".freeze
      NOTIFICATION_TAB = "#custom-notification-tab".freeze

      # The fund document tag the notice generator reads (CapitalDistributionPaymentDocJob)
      TEMPLATE_TAG = "Distribution Template".freeze

      private

      def routes
        Rails.application.routes.url_helpers
      end

      def payments(dist)
        dist.capital_distribution_payments
      end

      # Payments that get a notice and an email
      def emailable_payments(dist)
        payments(dist).where.not(capital_commitment_id: dist.skip_doc_gen_commitment_ids)
      end

      # Generated distribution notices (not templates) on the given payments
      def generated_notices(dist, payment_scope = payments(dist))
        ::Document.not_templates.where(owner_type: "CapitalDistributionPayment", owner_id: payment_scope.select(:id),
                                       owner_tag: "Generated")
      end

      def distribution_path(dist)
        routes.capital_distribution_path(dist)
      end

      # This distribution's generated notices still awaiting approval, with the Documents screen's
      # approval banner. Plain ransack params, so step_results stay identical between evaluations.
      def pending_notices_path(dist)
        routes.documents_path(no_folders: true, filter: true, hint: "approve_notices",
                              q: { capital_distribution_id_eq: dist.id, owner_tag_cont: "Generated", approved_eq: false })
      end

      # Why investors are not emailed for this distribution, or nil when they are. Matches the
      # conditions CapitalDistributionPayment#send_notification checks before emailing.
      # Worked examples E2, E3 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
      def no_email_reason(dist)
        return "Imported distribution — investors are not emailed" if dist.manual_generation
        return "Investors are not emailed for this distribution" unless dist.send_notification_on_complete
        return "Every commitment is set to Skip Doc Gen" if payments(dist).exists? && !emailable_payments(dist).exists?

        nil
      end

      # The fund has a notice template. Commitment templates only override a fund template of the
      # same name (CommitmentDocuments#templates), so without a fund template no notice is made.
      # Worked examples E1 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
      def notice_template?(dist)
        dist.fund.documents.templates.exists?(owner_tag: TEMPLATE_TAG)
      end

      # True once every emailable payment has been emailed (and there is at least one)
      def all_emailed?(dist)
        scope = emailable_payments(dist)
        scope.exists? && !scope.exists?(notification_sent: false)
      end
    end
  end
end
