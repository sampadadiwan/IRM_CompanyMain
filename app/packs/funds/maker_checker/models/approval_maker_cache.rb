# frozen_string_literal: true

# ② Per-request / per-job memo for the change watcher (M13 design card ②, D3).
#
# - seen: the (record, person) pairs already written to the preparer log in this request or job, so generating
#   3,000 remittances under one person costs one INSERT, not 3,000 (E8).
# - withdrawn: the records whose approval was withdrawn in this request, so the controller that made the change
#   can add "Its approval was withdrawn…" to its flash even when the withdrawal happened on another copy of the
#   record (a remittance edit withdraws its call through a freshly locked row, H21–H23).
# - exempt: whether a parent is an open-ended settlement, once per parent — a generation job loads the parent afresh
#   for every remittance / payment it creates, so a per-instance memo alone would ask once per row (Prosopite).
#
# Kept out of Current, which by its own rule holds only the acting user (like LpPortfolioVisibilityCache). Rails
# clears every CurrentAttributes at the start and end of each request and job.
class ApprovalMakerCache < ActiveSupport::CurrentAttributes
  attribute :seen, :withdrawn, :exempt

  class << self
    # E8 / E9 — has this person already been recorded for this record in this request / job?
    def seen?(record, user)
      seen_set.include?(key(record, user))
    end

    def mark(record, user)
      seen_set << key(record, user)
    end

    # A rolled-back change records nobody, so forget it and let a later change in the same request insert again
    def forget(record, user)
      seen_set.delete(key(record, user))
    end

    # H21–H23 — the approval of this record was withdrawn in this request / job
    def withdrawn!(record)
      withdrawn_set << record_key(record)
    end

    def withdrawn?(record)
      withdrawn_set.include?(record_key(record))
    end

    # E27 / E50 — the open-ended-settlement answer for this record, computed once per request / job
    def exempt?(record)
      self.exempt ||= {}
      key = record_key(record)
      return exempt[key] if exempt.key?(key)

      exempt[key] = yield
    end

    private

    def seen_set
      self.seen ||= Set.new
    end

    def withdrawn_set
      self.withdrawn ||= Set.new
    end

    def record_key(record)
      "#{record.class.polymorphic_name}:#{record.id}"
    end

    def key(record, user)
      "#{record_key(record)}:#{user.id}"
    end
  end
end
