# 1. Create remittances — every commitment in the call's closes with a positive committed amount has
# a remittance (generated calls; the generator skips zero commitments, and adds remittances for
# commitments admitted later), or the call's remittance uploads have all finished (Upload calls).
# Checked against production data: 180 of the last 200 generated calls pass this rule; the rest
# genuinely lack remittances (design Decision 13). After a figures change, the evaluator also needs a
# "recomputed" marker newer than the change — fresh_since is the oldest remittance so that only the
# marker (Recompute Call) can satisfy it.
# Worked examples H2, E21 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
module WorkflowChecks
  module CapitalCall
    class CreateRemittances < WorkflowChecks::Base
      include Support

      self.key = "capital_call.create_remittances"
      self.label = "Create remittances"
      self.workflowable_type = "CapitalCall"
      # What the step popup says (journey_step_info): what to do, why the step exists, and what
      # completing it changes — including whether anyone outside the team is emailed
      self.how = "Generated calls: Recompute Call creates any missing remittances. Upload calls: upload the remittance sheet from the Remittances tab."
      self.why = "Everything after this (notices, emails, payments) runs per remittance, so a missing one means an investor is never called."
      self.effects = "Each investor's remittance (amount and fees) appears on the Remittances tab. No emails are sent."

      def call(call)
        call.call_basis == "Upload" ? uploaded(call) : generated(call)
      end

      private

      def generated(call)
        expected = call.applicable_to.where("capital_commitments.committed_amount_cents > 0")
        expected_count = expected.count
        missing = expected.where.not(id: remittances(call).select(:capital_commitment_id)).count
        if expected_count.zero? || missing.positive?
          created = expected_count - missing
          # Recompute Call is what creates the missing ones (and the marker a figures change needs)
          return fail_with(message: "#{created} of #{expected_count} remittances created",
                           action_label: "Recompute Call", action_path: call_path(call), action_target: RECOMPUTE_BTN)
        end

        done(call, "#{remittances(call).count} remittances created")
      end

      # Upload calls have no generator, so the way forward is the import page itself — the button goes
      # straight there rather than to the Remittances tab's Upload / Download menu
      def uploaded(call)
        unless remittances(call).exists?
          return fail_with(message: "No remittances uploaded yet", action_label: "Upload Remittances",
                           action_path: upload_remittances_path(call))
        end

        uploads = ::ImportUpload.where(id: remittances(call).where.not(import_upload_id: nil).select(:import_upload_id))
        return fail_with(message: "Remittance upload in progress") if uploads.where(status: nil).where("processed_row_count < total_rows_count").exists?(created_at: 1.day.ago..)
        # A failed row only counts in failed_row_count — the upload still ends "Completed"
        # (capital-distribution-journey code review)
        if uploads.where.not(status: [nil, "", "Completed"]).or(uploads.where(failed_row_count: 1..)).exists?
          # Re-importing is the fix; the import page lists the earlier upload's errors
          return fail_with(message: "Remittance upload failed — fix and re-import", action_label: "Upload Remittances",
                           action_path: upload_remittances_path(call))
        end

        done(call, "#{remittances(call).count} remittances uploaded")
      end

      def done(call, message)
        pass(message:, passed_since: remittances(call).maximum(:created_at), fresh_since: remittances(call).minimum(:created_at))
      end
    end
  end
end
