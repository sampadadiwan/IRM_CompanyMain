# frozen_string_literal: true

# ③ Who prepared this capital call / distribution, and the firm's maker–checker switch, as the approval rule (④),
# the pages (⑥) and the notices (⑦) read them (OWASP review 2026-11 M13,
# openspec/changes/archive/2026-11-10-capital-call-distribution-maker-checker, design card ③, LLD "Method Contracts").
#
# Included in CapitalCall and CapitalDistribution, next to ApprovalFigureWatch (②), which calls record_preparer!.
# Every read is memoised on the record instance, so one page asks the database at most three times (Query budget).
module WithApprovalMakers
  extend ActiveSupport::Concern

  included do
    # Append-only rows (D2). No dependent: the records are soft-deleted (Trackable → acts_as_paranoid), and paranoia
    # runs dependent callbacks on a soft delete too, which would lose the log of a restored record (C19)
    has_many :approval_makers, as: :approvable
  end

  # The dealing-date column that makes a record an open-ended settlement (maker_checker_exempt?)
  SETTLEMENT_COLUMNS = { "CapitalCall" => :subscription_call_id, "CapitalDistribution" => :redemption_distribution_id }.freeze

  class_methods do
    # X7 / X8 — bulk approve asks the rule for many records: their preparer log, creator audits and settlement links
    # in three queries, as { id => [creator_id, [[user_id, role], …], settled?] }, so the per-record policy check
    # asks the database nothing more (Query budget). Each record takes its entry with preload_preparer_entries.
    def approval_maker_entries_for(ids)
      return {} if ids.blank?

      # The log, oldest first, per record
      rows = ApprovalMaker.where(approvable_type: polymorphic_name, approvable_id: ids).order(:id)
                          .pluck(:approvable_id, :user_id, :role).group_by(&:first)
      # The first create audit per record (only ids read, never audited_changes)
      creators = {}
      Audited.audit_class.where(auditable_type: polymorphic_name, auditable_id: ids, action: "create").order(:version)
             .pluck(:auditable_id, :user_id).each { |record_id, user_id| creators[record_id] ||= user_id }
      # Open-ended settlements (maker_checker_exempt?)
      column = WithApprovalMakers::SETTLEMENT_COLUMNS.fetch(polymorphic_name)
      settled = DealingDate.where(column => ids).pluck(column).to_set
      ids.index_with do |id|
        [creators[id], (rows[id] || []).map { |_, user_id, role| [user_id, role] }, settled.include?(id)]
      end
    end
  end

  # ② → ③ — writes the person to the preparer log, at most once per record per person.
  # E8 / E9 — ApprovalMakerCache skips a repeat in the same request / job (3 generated remittances → 1 row); the
  # unique index makes a repeat in a later request a no-op (insert_all skips duplicates on MySQL and SQLite).
  def record_preparer!(user, role:)
    # E10 — no acting person records nobody; an unsaved record has no id to log against yet
    return true if user.nil? || !persisted?
    # E8 / E9 — already written for this person in this request / job
    return true if ApprovalMakerCache.seen?(self, user)

    # One row; a duplicate (an earlier request) is skipped by the unique index, never raised
    ApprovalMaker.insert_all([{ entity_id:, approvable_type: self.class.polymorphic_name, approvable_id: id,
                                user_id: user.id, role: role.to_s, created_at: Time.current }])
    ApprovalMakerCache.mark(self, user)
    # The next read sees the new person
    reset_approval_maker_memos
    true
  end

  # [[user_id, role], …] in the order people prepared the record: the create-audit user first (D4), then the log
  def preparer_entries
    return [] unless persisted?

    @preparer_entries ||= begin
      # E12 / E13 — the creator from the audit trail counts even when the log has no row for them (legacy records)
      creator_id = approval_creator_id
      entries = creator_id ? [[creator_id, "created"]] : []
      # The log, oldest first; a person already listed keeps their first role
      ApprovalMaker.where(approvable_type: self.class.polymorphic_name, approvable_id: id).order(:id)
                   .pluck(:user_id, :role).each do |user_id, role|
        entries << [user_id, role] unless entries.any? { |listed_id, _| listed_id == user_id }
      end
      entries
    end
  end

  # The batch preload above, for one record: the same entries preparer_entries would read
  def preload_preparer_entries(creator_id, rows, settled)
    entries = creator_id ? [[creator_id, "created"]] : []
    rows.each { |user_id, role| entries << [user_id, role] unless entries.any? { |listed_id, _| listed_id == user_id } }
    @preparer_entries = entries
    @maker_checker_exempt = evergreen_settlement_flag.present? || settled
  end

  # ③ → ④ — every preparer's user id (log rows ∪ the create-audit user, D4)
  def preparer_ids
    preparer_entries.map(&:first)
  end

  # The preparers as users, in the order they prepared it (deactivated users included: they still prepared it)
  def preparers
    @preparers ||= begin
      ids = preparer_ids
      by_id = ids.empty? ? {} : User.with_deleted.where(id: ids).index_by(&:id)
      ids.filter_map { |user_id| by_id[user_id] }
    end
  end

  # D12 / H14 / H17 — self-approval is derived, never stored: the approver is one of the preparers
  def approved_by_preparer?
    approved && approved_by_user_id.present? && preparer_ids.include?(approved_by_user_id)
  end

  # ① → ④ — the firm's switch, read from the record's own firm (never the user's, X9)
  def maker_checker_on?
    return @maker_checker_on if defined?(@maker_checker_on)

    @maker_checker_on = entity&.entity_setting&.approval_maker_checker == true
  end

  # D14 / E27 / E31 / E50 — open-ended (evergreen) settlement records are created approved by a dealing date and are
  # never watched or withdrawn; the same test that keeps them out of journeys (skip_journey?)
  def maker_checker_exempt?
    return skip_journey? unless persisted?
    return @maker_checker_exempt if defined?(@maker_checker_exempt)

    # Once per record per request / job, whichever copy of the record asks (ApprovalMakerCache)
    @maker_checker_exempt = ApprovalMakerCache.exempt?(self) { skip_journey? }
  end

  # H21–H23 — this record's approval was withdrawn in this request (on this copy or on a freshly locked one)
  def approval_withdrawn?
    persisted? && ApprovalMakerCache.withdrawn?(self)
  end

  def reload(*)
    reset_approval_maker_memos
    remove_instance_variable(:@maker_checker_on) if defined?(@maker_checker_on)
    remove_instance_variable(:@maker_checker_exempt) if defined?(@maker_checker_exempt)
    super
  end

  private

  # D4 — the user of the record's create audit: one indexed row (auditable_index), only user_id read, never the
  # wide audited_changes column
  def approval_creator_id
    audits.where(action: "create").order(:version).limit(1).pick(:user_id)
  end

  def reset_approval_maker_memos
    @preparer_entries = nil
    @preparers = nil
  end
end
