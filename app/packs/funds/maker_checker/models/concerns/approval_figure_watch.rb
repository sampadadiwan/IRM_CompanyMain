# frozen_string_literal: true

# ② The change watcher (OWASP review 2026-11 M13, openspec/changes/archive/2026-11-10-capital-call-distribution-maker-checker, design
# card ②, D3, D8, D14; LLD "Method Contracts", "Transactions").
#
# Included in the six models whose figures decide what LPs pay or receive: CapitalCall and CapitalDistribution (the
# records that are approved) and CapitalRemittance, CapitalDistributionPayment, CallFee, DistributionFee (their
# children). Each model names its figure columns once, next to the include:
#
#   watches_approval_figures APPROVAL_FIGURES, parent: :capital_call
#
# When a person (Current.user — the real person, CapHive support when acting as a user, D9) creates or changes a
# figure, they are written to the parent's preparer log (③). With the firm's maker–checker setting on, a figure change
# on an approved parent withdraws its approval in the same transaction (⑧), so figures and approval never disagree.
#
# Callbacks only record and flag — no business flow. Everything runs inside the caller's transaction: a rolled-back
# change records nobody and withdraws nothing.
module ApprovalFigureWatch
  extend ActiveSupport::Concern

  included do
    class_attribute :approval_figures, instance_writer: false, default: [].freeze
    class_attribute :approval_parent_name, instance_writer: false, default: nil
    # Remittances / payments: a row created in an already-approved parent is catch-up for a new commitment (E43)
    class_attribute :approval_creates_are_catch_up, instance_writer: false, default: false

    # ⑧ The parent's own figures: withdraw in the same save, so the audit row shows the figure and the approval change
    before_save :withdraw_own_approval_on_figure_change, if: :approval_parent_itself?
    # ② record the preparer (and, for a child, withdraw the parent's approval) inside the transaction
    after_save :watch_approval_figures
    after_destroy :watch_approval_figures_on_destroy
    # A rolled-back change wrote no row, so the per-request memo must not claim it did
    after_rollback :forget_approval_maker
  end

  class_methods do
    # The model's figure columns; for a child, the association that leads to the approved record, and whether a row
    # created under an approved parent is catch-up rather than a change (remittances and payments for a late
    # commitment, E43) — a fee line added after approval is a change (design card ②)
    def watches_approval_figures(figures, parent: nil, creates_are_catch_up: false)
      self.approval_figures = figures.map(&:to_s).freeze
      self.approval_parent_name = parent
      self.approval_creates_are_catch_up = creates_are_catch_up
    end
  end

  # The capital call / distribution whose approval these figures belong to (self for the parents)
  def approval_parent
    approval_parent_itself? ? self : public_send(approval_parent_name)
  end

  def approval_parent_itself?
    approval_parent_name.nil?
  end

  private

  # ⑧ D8 — a person changes a figure of an approved call / distribution itself (H21, E53)
  def withdraw_own_approval_on_figure_change
    # Only an update of an approved record; approving it (approved changing in this save) is never a withdrawal
    return unless persisted? && approved && !will_save_change_to_approved?
    # E40 — name, notes, custom fields, notification switches: not figures
    return unless changes_to_save.keys.intersect?(approval_figures)
    # E44 — setting off: today's behaviour. E50 — open-ended settlements are system-approved
    return unless maker_checker_on? && !maker_checker_exempt?

    actor = Current.user
    # E45 — nobody behind the change (a cron job, a console): keep the approval, tell engineering
    return log_unattributed_figure_change(self) if actor.nil?

    ApprovalWithdraw.withdraw_in_place(self, actor)
  end

  # ② after create / update, inside the transaction
  def watch_approval_figures
    creating = previously_new_record?
    # E4–E7, E14 — nothing a person did here moved a figure (an update that saved no figure column)
    return if !creating && !saved_changes.keys.intersect?(approval_figures)

    parent = approval_parent
    # E27 / E31 / E50 — open-ended settlements are created approved by a dealing date and never watched
    return if parent.nil? || parent.maker_checker_exempt?

    actor = Current.user
    if actor.nil?
      # E10 / E45 — no acting person records nobody; a changed figure on an approved parent is logged (the parent's
      # own change was logged in before_save). Setting off: nothing is withdrawn, so nothing is logged
      log_unattributed_figure_change(parent) if !creating && !approval_parent_itself? && parent.approved && parent.maker_checker_on?
      return
    end

    # E43 — a remittance / payment created in an already-approved parent is catch-up for a new commitment
    # (CapitalCommitmentRemittanceJob), not re-preparing: nobody is recorded and the approval stays
    return if creating && approval_creates_are_catch_up && parent.approved

    # H2–H11 — the creator, importer or editor of figures is a preparer (E8 / E9: once per record per person)
    parent.record_preparer!(actor, role: approval_maker_role(creating))
    # H22 / H23 / E46 — a child's figure changed (or a fee line was added) under an approved parent: withdraw it
    # (setting on, checked inside). The parent's own change was withdrawn in before_save.
    ApprovalWithdraw.call(record: parent, actor:) if !approval_parent_itself? && parent.approved
  end

  # E48 — a remittance / payment / fee line deleted by a person changes what LPs pay or receive
  def watch_approval_figures_on_destroy
    # E49 — the parent itself is being deleted (dependent: :destroy): nothing to record or withdraw
    return if destroyed_by_association.present?

    parent = approval_parent
    # E49 — the parent is being (soft-)deleted itself: paranoia marks it deleted before its dependents go, and does not
    # always flag them destroyed_by_association
    return if parent.nil? || parent.destroyed? || parent.try(:deleted_at).present? || parent.maker_checker_exempt?

    actor = Current.user
    # E45 — nobody behind it: keep the approval, tell engineering
    # (only for firms with the setting on — with it off nothing is withdrawn, so there is nothing to report)
    return log_unattributed_figure_change(parent) if actor.nil? && parent.approved && parent.maker_checker_on?
    return if actor.nil?

    parent.record_preparer!(actor, role: :edited)
    ApprovalWithdraw.call(record: parent, actor:) if parent.approved
  end

  # How the person became a preparer (the "Prepared by" tooltip only; the rule ignores it)
  def approval_maker_role(creating)
    return :imported if try(:import_upload_id).present?

    creating && approval_parent_itself? ? :created : :edited
  end

  # Forget the memo for a change that rolled back, so a retry in the same request records the person
  def forget_approval_maker
    actor = Current.user
    parent = approval_parent if actor
    ApprovalMakerCache.forget(parent, actor) if parent&.id
  rescue ActiveRecord::RecordNotFound
    nil
  end

  # E45 — ids only, never names (LLD "Error Mapping and Logging")
  def log_unattributed_figure_change(parent)
    Rails.logger.warn("[MakerChecker] unattributed figure change #{self.class.name}=#{id} " \
                      "#{parent.class.name}=#{parent.id} entity=#{parent.entity_id} — approval kept")
    nil
  end
end
