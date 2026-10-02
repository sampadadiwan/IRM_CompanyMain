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

      # The KYC's AML result as "no_match" / "potential_match" / nil. Overrides store the snake_case
      # value, while AmlReportAsyncDownloadJob copies the report's titleized "No Match" — accept both.
      def aml_result(kyc)
        kyc.aml_status.presence&.parameterize(separator: "_")
      end

      def submitted?(kyc)
        SUBMITTED.include?(kyc.submission_status)
      end

      # The names of the documents this KYC must have: the entity's list for its KYC type (Settings →
      # individual / non-individual KYC documents, as InvestorKycConcern#docs_completed? reads it) plus
      # the KYC form's required document fields (as InvestorKyc#check_required_file_type_custom_fields
      # names them). Order kept, duplicates removed.
      def required_document_names(kyc)
        setting = kyc.entity.entity_setting
        list = kyc.individual? ? setting&.individual_kyc_doc_list : setting&.non_individual_kyc_doc_list
        names = list.to_s.split(",").map(&:strip).compact_blank
        if kyc.form_type_id
          ::FormCustomField.where(form_type_id: kyc.form_type_id, field_type: "File", required: true)
                           .pluck(:label, :name).each { |label, name| names << (label.presence || name.to_s.humanize) }
        end
        names.uniq
      end

      # Required names with no document of that name on the KYC (one distinct-names query)
      def missing_document_names(kyc)
        required = required_document_names(kyc)
        return [] if required.empty?

        present = ::Document.where(owner_type: "InvestorKyc", owner_id: kyc.id).distinct.pluck(:name)
        required - present
      end

      # [failed, total] answers in the stored AI validation results; nil when AI validation has not run.
      # "Failed" is the validator's own rule (DocLlmValidator::NO_LIST), so it agrees with all_docs_valid.
      def ai_answer_counts(kyc)
        answers = kyc.doc_question_answers
        return nil unless answers.is_a?(Hash) && answers.any?

        responses = answers.values.grep(Hash).flat_map(&:values)
        failed = responses.count { |r| !r.is_a?(Hash) || DocLlmValidator::NO_LIST.include?(r["answer"].to_s.downcase) }
        [failed, responses.size]
      end

      # When AI validation last wrote its results (the newest audit touching them): the evidence time
      # for "Validated by AI", compared with any invalidation (a document changed afterwards)
      def ai_validated_at(kyc)
        kyc.audits.where("audited_changes LIKE ? OR audited_changes LIKE ?", "%all_docs_valid%", "%doc_question_answers%")
           .maximum(:created_at)
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
