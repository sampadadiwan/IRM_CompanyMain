# frozen_string_literal: true

# ⑦ The one place that decides who is told what about maker–checker (OWASP review 2026-11 M13,
# openspec/changes/capital-call-distribution-maker-checker, design card ⑦, "Notifications", D11, D13; LLD "Method
# Contracts", "Queries and Indexes"). Modelled on ComplianceNotices.
#
# Recipients are always people of the record's own firm — never investors, advisors, another firm or CapHive support
# (X13–X15, E32). Every notice is an email + a bell row (MakerCheckerNotifier), and only ever sent after the change
# commits.
module MakerCheckerNotices
  # The answer to Request approval (⑥): sent to whom, or why nothing was sent
  Result = Struct.new(:sent, :recipients, :error, :asked_at, keyword_init: true) do
    def sent? = sent
  end

  # D11 — Request approval at most once an hour per record
  THROTTLE = 1.hour

  KINDS = %w[approval_request approval_withdrawn maker_checker_off].freeze

  module_function

  # E32 / E33 — the people who could approve this record right now: active users of the record's firm with the
  # Approver role and edit access to its fund, who did not prepare it. ≤ 3 queries whatever the firm's size: the users
  # with their roles, then one access-rights read for the fund (no per-user policy query, LLD "Queries").
  def checkers(record)
    preparer_ids = record.preparer_ids
    approvers_with_access(record).reject { |user| preparer_ids.include?(user.id) }
  end

  # H18 / H20 — Request approval: tell every checker. E34 — none: send nothing and say how to fix it. E35 / E36 —
  # refused within an hour of the last request for this record.
  def request(record, user)
    # E35 — asked within the hour: nothing is sent; the message says when they can ask again
    asked_at = last_request_at(record)
    return Result.new(sent: false, recipients: [], error: :throttled, asked_at:) if asked_at && asked_at > THROTTLE.ago

    recipients = checkers(record)
    # E34 — nobody else can approve: nothing is sent
    return Result.new(sent: false, recipients: [], error: :no_checker) if recipients.empty?

    message = "#{record} (#{record.fund.name}) needs your approval"
    deliver(recipients, record, "approval_request", message, actor: user)
    Result.new(sent: true, recipients:, error: nil)
  end

  # ⑥ The flash after Request approval (both controllers): [:notice | :alert, text]. Times are the screen's own
  # format (time_only, CLAUDE.md "Date formatting"); the request itself is refused, never half-sent.
  def request_flash(result, record)
    noun = record.is_a?(CapitalDistribution) ? "distribution" : "call"
    case result.error
    when nil
      # H18 / H20
      [:notice, "Approval requested from #{result.recipients.map(&:full_name).to_sentence}."]
    when :throttled
      # E35
      asked = I18n.l(result.asked_at, format: :time_only)
      again = I18n.l(result.asked_at + THROTTLE, format: :time_only)
      [:alert, "Approvers were already asked at #{asked}. You can ask again after #{again}."]
    else
      # E34
      [:alert, "No one else can approve this #{noun}. Ask a company admin to give the Approver role to a colleague " \
               "with access to this fund, or turn off maker–checker in Settings."]
    end
  end

  # H21–H23 — the sentence the update actions add to their notice when the change withdrew an approval
  def withdrawn_sentence
    "Its approval was withdrawn because the figures changed — another approver must approve it again."
  end

  # H22 / H23 — after a withdrawal commits: the checkers and the preparers, minus the person who changed the figures.
  # E51 — when investors were already sent the notice, the alert says they are not told about the change.
  def withdrawn(record, actor)
    recipients = (approvers_with_access(record) + preparers_with_access(record)).uniq.reject { |user| user.id == actor&.id }
    message = "Approval of #{record} was withdrawn: #{actor.full_name} changed its figures after approval."
    message += " Investors were already sent this #{record_noun(record)}'s notice; they are not told about the change." if investors_already_told?(record)
    deliver(recipients, record, "approval_withdrawn", message, actor:)
    recipients.size
  end

  # H25 / D13 — the setting was switched off: every other active company admin and approver of the firm is told.
  # Dates in a .rb file go through I18n.l(format: :email, locale: :en) (CLAUDE.md "Date formatting").
  def switched_off(setting, actor)
    entity = setting.entity
    recipients = User.where(entity_id: entity.id, active: true).includes(:roles).to_a.select do |user|
      user.has_cached_role?(:company_admin) || user.has_cached_role?(:approver)
    end
    recipients.reject! { |user| user.id == actor&.id }
    who = actor&.full_name || "an automatic job"
    message = "Maker–checker for calls and distributions was turned off by #{who} on " \
              "#{I18n.l(Time.zone.today, format: :email, locale: :en)}."
    recipients.each do |user|
      MakerCheckerNotifier.with(record: user, entity_id: entity.id, kind: "maker_checker_off", message:,
                                actor_id: actor&.id).deliver(user)
    end
    recipients.size
  end

  # ── recipients ───────────────────────────────────────────────────────────────

  # Active users of the record's firm with the Approver role who can edit the record (the update? half of approve?):
  # company admins always can; anyone else needs an access right with update on the fund
  def approvers_with_access(record)
    users = User.where(entity_id: record.entity_id, active: true).includes(:roles).to_a
                .select { |user| user.has_cached_role?(:approver) }
    with_edit_access(record, users)
  end

  # The record's preparers who still belong to the firm, are active and can edit it
  def preparers_with_access(record)
    ids = record.preparer_ids
    return [] if ids.empty?

    users = User.where(id: ids, entity_id: record.entity_id, active: true).includes(:roles).to_a
    with_edit_access(record, users)
  end

  # E32 — Tara (Approver, no fund access) is left out; one access-rights query for everyone who is not a company admin
  def with_edit_access(record, users)
    admins, others = users.partition { |user| user.has_cached_role?(:company_admin) }
    return admins if others.empty?

    fund = record.fund
    editors = AccessRight.where(entity_id: fund.entity_id, owner_type: fund.class.name, owner_id: fund.id,
                                user_id: others.map(&:id))
                         .select { |right| right.permissions.set?(:update) }.map(&:user_id)
    admins + others.select { |user| editors.include?(user.id) }
  end

  # ── delivery ─────────────────────────────────────────────────────────────────

  def deliver(users, record, kind, message, actor: nil)
    users.each do |user|
      # Only the record's own firm, never an investor (X14) — recipients are built that way; checked again here
      next unless user.entity_id == record.entity_id

      MakerCheckerNotifier.with(record: user, entity_id: record.entity_id, kind:, message:,
                                approvable_type: record.class.polymorphic_name, approvable_id: record.id,
                                actor_id: actor&.id).deliver(user)
    end
  end

  # D11 — the newest approval request for this record in the last hour. The events table is filtered by type and
  # time (a handful of rows an hour firm-wide); the record is matched in Ruby to stay MySQL / SQLite neutral (LLD).
  def last_request_at(record)
    MakerCheckerNotifier.where(created_at: THROTTLE.ago..).order(created_at: :desc).limit(500).to_a
                        .select { |event| request_for?(event, record) }.map(&:created_at).max
  end

  def request_for?(event, record)
    params = event.params.to_h.with_indifferent_access
    params[:kind] == "approval_request" && params[:approvable_type] == record.class.polymorphic_name &&
      params[:approvable_id].to_i == record.id
  end

  def investors_already_told?(record)
    case record
    when CapitalCall then record.any_remittance_notified?
    when CapitalDistribution then record.capital_distribution_payments.exists?(notification_sent: true)
    else false
    end
  end

  def record_noun(record)
    record.is_a?(CapitalCall) ? "call" : "distribution"
  end
end
