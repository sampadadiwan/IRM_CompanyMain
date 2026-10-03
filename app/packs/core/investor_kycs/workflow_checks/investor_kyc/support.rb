# Shared helpers for the investor KYC journey checks. Everything here reads; nothing writes.
#
# A check looks only at the one KYC row and its own documents, AML reports, audits and the entity's
# settings — never at other KYCs — so each costs a handful of indexed lookups.
# Inside this module ::InvestorKyc is the model; bare InvestorKyc is the namespace.
# Worked examples H2, E1, E3 — openspec/changes/investor-kyc-journey/design.md#worked-examples
module WorkflowChecks
  module InvestorKyc
    module Support
      # Controls on the KYC's OWN page (investor_kycs/show.html.erb, _send_notifications, _details).
      # A step whose work is done by one of these sets it as its action_target, so the journey panel
      # clicks that control instead of linking to the page the user is on. "#..." is a tab to open.
      # Keep in step with those views; a missing target falls back to action_path.
      EDIT_BTN = "investor_kyc_edit_btn".freeze
      VALIDATE_AI_BTN = "investor_kyc_validate_docs_with_ai_btn".freeze
      AML_GENERATE_BTN = "investor_kyc_generate_new_aml_report_btn".freeze
      AML_VIEW_BTN = "investor_kyc_view_aml_reports_btn".freeze
      VERIFY_BTN = "investor_kyc_toggle_verified_btn".freeze
      DOCS_TAB = "#docs-tab".freeze
      VALIDATION_TAB = "#docs-validation-tab".freeze

      # submission_status values meaning the investor (or the fund) has submitted
      SUBMITTED = %w[completed verified].freeze

      # The email the KYC form link is sent with — the one "Set up KYC email" and "Preview the email"
      # are about. The reminder (kyc_required_reminder) repeats it and has no review of its own.
      KYC_REQUIRED_METHOD = "notify_kyc_required".freeze

      private

      def routes
        Rails.application.routes.url_helpers
      end

      def kyc_path(kyc)
        routes.investor_kyc_path(kyc)
      end

      def edit_kyc_path(kyc)
        routes.edit_investor_kyc_path(kyc)
      end

      # The KYC Actions item that sends this email: with the entity's own custom notification template
      # the item is "..._custom_0_btn" (investor_kycs/_send_notifications.html.erb), otherwise "..._default_btn"
      def email_button_id(kyc, email_method)
        custom = kyc.entity.custom_notifications.for_type("InvestorKyc").exists?(email_method:)
        "investor_kyc_#{email_method}_#{custom ? 'custom_0' : 'default'}_btn"
      end

      # The KYC Actions item that PREVIEWS this email, the mirror of email_button_id: with the
      # entity's own template the item is "..._custom_0_btn", otherwise "..._default_btn"
      # (investor_kycs/_preview_notifications.html.erb builds both the same way).
      # Worked examples H4 — openspec/changes/investor-kyc-email-review-steps/design.md#worked-examples
      def preview_button_id(kyc, email_method)
        custom = kyc.entity.custom_notifications.for_type("InvestorKyc").exists?(email_method:)
        "investor_kyc_preview_#{email_method}_#{custom ? 'custom_0' : 'default'}_btn"
      end

      # The KYC-required email this investor will actually receive, or nil when the company has set
      # none up. Resolved through Entity#custom_notification — the very call InvestorKycMailer#set_kyc
      # makes (enabled, last one wins) — so the journey can never name an email the send would not
      # use. A disabled template therefore reads as "none set up", exactly as it behaves on a send.
      # Worked examples H1, H2, E14 — openspec/changes/investor-kyc-email-review-steps/design.md#worked-examples
      def kyc_required_notification(kyc)
        kyc.entity.custom_notification(KYC_REQUIRED_METHOD, for_type: "InvestorKyc")
      end

      # The entity's KYC emails, filtered — the same list the KYC index's "View All Custom
      # Notifications" item opens. RansackQueryBuilder.single is idx-keyed and so deterministic;
      # .multiple generates random group keys per call, which would make this link (and so
      # step_results) differ on every evaluation, turning each page view into a write.
      def kyc_notifications_path(_kyc)
        routes.custom_notifications_path(q: RansackQueryBuilder.single("for_type", :eq, "InvestorKyc"))
      end

      # The new-email form, pre-filled for KYC emails, as the KYC index's "Custom KYC Notification" item
      def new_kyc_notification_path(kyc)
        routes.new_custom_notification_path('custom_notification[for_type]': "InvestorKyc",
                                            'custom_notification[entity_id]': kyc.entity_id)
      end

      # The KYC's AML result as "no_match" / "potential_match" / nil. Overrides store the snake_case
      # value, while AmlReportAsyncDownloadJob copies the report's titleized "No Match" — accept both.
      def aml_result(kyc)
        kyc.aml_status.presence&.parameterize(separator: "_")
      end

      def submitted?(kyc)
        SUBMITTED.include?(kyc.submission_status)
      end

      # The names of the documents this KYC must have (InvestorKycConcern#required_document_names, shared
      # with Document Checks so both agree on which documents a KYC has)
      def required_document_names(kyc)
        kyc.required_document_names
      end

      # Required names no document on the KYC satisfies — matched by name or owner_tag, ignoring case and
      # an "Upload "/"Attach your " prefix (InvestorKycConcern#missing_required_document_names)
      def missing_document_names(kyc)
        kyc.missing_required_document_names(required_document_names(kyc))
      end

      # When the KYC was last set to verified (the audit of the submission_status change), or nil
      def verified_at(kyc)
        kyc.audits.where(action: "update").where("audited_changes LIKE ?", "%submission_status%").order(created_at: :desc).limit(20)
           .find { |a| Array(a.audited_changes["submission_status"]).last == "verified" }&.created_at
      end

      def date(value)
        I18n.l(value.to_date)
      end
    end
  end
end
