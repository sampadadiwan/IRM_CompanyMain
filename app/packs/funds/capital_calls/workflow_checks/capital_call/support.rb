# Shared helpers for the capital call journey checks. Everything here reads; nothing writes.
#
# "Notifiable" remittances are those whose commitment is not set to skip document generation —
# the same rule CapitalCallJob#notify and the doc generator use. skip_doc_gen lives in
# capital_commitments.json_fields, so it is filtered in Ruby over two narrow columns (portable to
# the SQLite test database; MySQL-only JSON SQL would not be).
#
# Every helper here returns a relation the callers count or probe with exists?, or selects ids
# only — nothing loads remittance or document rows, so a 5,000-remittance call costs the same as
# a 40-remittance one (CLAUDE.md large-table rules).
# Worked examples E19 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    module Support
      # Controls that already exist on the call's OWN page (capital_calls/show.html.erb and
      # _details.html.erb). A step whose work is done by one of these sets it as its action_target,
      # so the journey panel clicks that control instead of linking to the page the user is on.
      # A "#..." value is a tab to open; anything else is a button's DOM id.
      #
      # Keep these in step with those views. A target that no longer exists is not an error: the
      # journey-action Stimulus controller looks before it clicks and otherwise follows action_path.
      # Worked examples H18 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
      GENERATE_DOCS_BTN = "capital_call_generate_docs_btn".freeze
      APPROVE_BTN = "capital_call_approve_btn".freeze
      NOTIFY_BTN = "capital_call_notify_btn".freeze
      ALLOCATE_UNITS_BTN = "capital_call_allocate_units_btn".freeze
      RECOMPUTE_BTN = "capital_call_recompute_fees_btn".freeze
      REMITTANCES_TAB = "#remittances-tab".freeze
      # The Remittances tab's "Verify Pending Remittances" (capital_remittances/_bulk_actions)
      BULK_VERIFY_BTN = "capital_remittances_bulk_verify_btn".freeze
      # The Actions menu's "View Generated Notices To Approve" link (opens in a new window)
      VIEW_NOTICES_TO_APPROVE_BTN = "capital_call_view_notices_to_approve_btn".freeze

      private

      def routes
        Rails.application.routes.url_helpers
      end

      def remittances(call)
        call.capital_remittances
      end

      # Remittances that get a notice and an email
      def notifiable_remittances(call)
        remittances(call).where.not(capital_commitment_id: ::CapitalCommitment.skip_doc_gen_ids(call.fund.capital_commitments))
      end

      # Generated call notices (not templates) on this call's remittances
      def generated_notices(call, remittance_scope = remittances(call))
        ::Document.not_templates.where(owner_type: "CapitalRemittance", owner_id: remittance_scope.select(:id),
                                       owner_tag: "Generated")
      end

      def call_path(call)
        routes.capital_call_path(call)
      end

      # The call's own "New Call Notification" form (Notification tab → New Notification) — an override
      # of the call notice, reminder and payment emails for this call only
      def new_call_notification_path(call)
        routes.new_custom_notification_path('custom_notification[entity_id]': call.entity_id, 'custom_notification[owner_id]': call.id,
                                            'custom_notification[owner_type]': "CapitalCall")
      end

      # The import page the Remittances tab's "Upload Remittances" menu item opens — keep the params in
      # step with capital_remittances/_index.html.erb
      def upload_remittances_path(call)
        routes.new_import_upload_path('import_upload[owner_id]': call.id, 'import_upload[owner_type]': "CapitalCall",
                                      'import_upload[import_type]': "CapitalRemittance", sample_upload: "CAPITAL_REMITTANCE_SAMPLE")
      end

      # The same filtered Documents list the call page's "View Generated Documents" opens
      # Plain ransack params, not RansackQueryBuilder.multiple: that builder generates random group
      # keys on every call, which made this link — and so step_results — differ on every evaluation,
      # turning each page view and tick into a write (and, with real-time updates, a broadcast loop)
      # Only this call's generated notices still awaiting approval, with the Documents screen's
      # approval banner — the same list the Actions menu link opens. Plain ransack params (deterministic).
      def pending_notices_path(call)
        routes.documents_path(no_folders: true, filter: true, hint: "approve_notices",
                              q: { capital_call_id_eq: call.id, owner_tag_cont: "Generated", approved_eq: false })
      end

      def notices_path(call)
        routes.documents_path(no_folders: true, filter: true, q: { capital_call_id_eq: call.id, owner_tag_cont: "Generated" })
      end

      def notices_not_applicable?(call)
        call.manual_generation || !call.send_call_notice_flag
      end

      # True once every notifiable remittance has been sent its notice (and there is at least one)
      def notices_all_sent?(call)
        scope = notifiable_remittances(call)
        scope.exists? && !scope.exists?(notification_sent: false)
      end
    end
  end
end
