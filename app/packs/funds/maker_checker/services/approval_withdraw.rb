# frozen_string_literal: true

# ⑧ Withdrawal (OWASP review 2026-11 M13, openspec/changes/capital-call-distribution-maker-checker, design card ⑧,
# D8; LLD "Transactions, Locking and Concurrency").
#
# With the firm's maker–checker setting on, a person who changes the figures of an approved capital call or
# distribution (or of its remittances, payments or fee lines) un-approves it, inside the same transaction as the
# change, so "approved" always covers the figures LPs will receive. After the change commits, the journey moves back
# to "Approve" with a note and the approvers are told (MakerCheckerNotices.withdrawn).
#
# The effect of CapitalCallUnapprove (reset approved / approved_by_user, journey undo), applied inside the open
# transaction instead of as a separate action.
class ApprovalWithdraw
  class << self
    # ② → ⑧ for a child's change: lock the parent row, re-read it, un-approve it.
    # Returns true when withdrawn, false when there was nothing to withdraw (setting off, exempt, already unapproved).
    def call(record:, actor:)
      # E44 — setting off: today's behaviour. E50 — open-ended settlements are system-approved
      return false unless record.maker_checker_on? && !record.maker_checker_exempt?

      # Lock order child → parent (the child row is already locked by its own UPDATE); no path locks the other way.
      # A fresh copy: the caller's copy may be mid-save (nested fee lines) and must not be reloaded under it.
      fresh = record.class.lock.find_by(id: record.id)
      # E49 — the parent was deleted in this same change: nothing to withdraw, nobody to tell
      return false if fresh.nil?

      # E52 / "Sent once" — a second change in parallel waited on the lock and now finds it already unapproved
      unless fresh.approved
        mark_unapproved(record)
        return false
      end

      fresh.approved = false
      fresh.approved_by_user = nil
      # C-X16 (design "Changed during the build") — the withdrawal skips the parent's own validations: an unrelated
      # problem on the call (e.g. a duplicate name after a data fix) must not block the editor's change, and the
      # approval is still withdrawn. Audited (Trackable) with the editor as the user, like any save.
      fresh.save!(validate: false)
      # Later children in this request see the parent as unapproved and don't try again
      mark_unapproved(record)
      after_withdrawal(fresh, actor)
      true
    end

    # ⑧ for the parent's own change (H21, E53): set in the same save, so one audit row shows both changes
    def withdraw_in_place(record, actor)
      record.approved = false
      record.approved_by_user = nil
      after_withdrawal(record, actor)
      true
    end

    private

    # The caller's in-memory copy of the parent follows the database, without becoming a pending change of its own
    def mark_unapproved(record)
      return unless record.approved

      record.approved = false
      record.approved_by_user_id = nil
      record.clear_attribute_changes(%i[approved approved_by_user_id])
    end

    # The editor's flash (H21) and, after commit only, the journey note and the approvers' alert (H22). Nothing is
    # sent from inside the transaction: a rolled-back change tells nobody.
    def after_withdrawal(record, actor)
      ApprovalMakerCache.withdrawn!(record)
      started_at = Time.current
      ActiveRecord.after_all_transactions_commit do
        # H21 — the journey goes back to "Approve" with who changed the figures
        record.journey_undo_evaluate(note: "Approval withdrawn: #{actor.full_name} changed the figures", actor:, started_at:)
        # H22 — approvers and preparers (not the editor) are told
        MakerCheckerNotices.withdrawn(record, actor)
      end
    end
  end
end
