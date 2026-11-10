# frozen_string_literal: true

# ④ The change emails (OWASP review 2026-11 M14, openspec/changes/archive/2026-11-10-bank-detail-change-controls, design card ④, D8, D9;
# LLD "Background Jobs", "Queries").
#
# Enqueued by BankDetailChangeGuard after the KYC save that made a bank change commits. Sends, at most once each:
#   - the investor email to the investor's approved contacts subscribed to KYC emails (or to every topic) whose
#     access existed before the change (H7, E24, E25) — never an address held in the KYC itself (E26);
#   - the approver email + bell alert to the firm's KYC approvers who can see the KYC, except the maker (H8, E30).
# Each audience is claimed with a conditional UPDATE on its *_notified_at stamp before anything is sent, so a
# Sidekiq retry or a second run sends nothing twice (E28).
class BankDetailChangeNotifyJob < ApplicationJob
  queue_as :default

  # The change (or its KYC) was deleted before the job ran: nothing to tell anyone
  discard_on ActiveRecord::RecordNotFound

  def perform(change_id)
    Chewy.strategy(:sidekiq) do
      change = BankDetailChange.find(change_id)
      kyc = change.investor_kyc
      return if kyc.nil?

      # A replaced change whose investor email never went out is covered by the newer change's email (card ④ FAQ)
      return if change.status == "replaced" && change.investor_notified_at.nil?

      # H7 — the investor first, so the approver email can say who was told (X6 when nobody)
      notify_investor(change, kyc) if claim(change, :investor_notified_at)
      # H8 — then the approvers
      notify_approvers(change.reload, kyc) if claim(change, :approvers_notified_at)
    end
  end

  private

  # E28 — at most once per audience: only the run that sets the stamp sends
  def claim(change, column)
    BankDetailChange.where(id: change.id, column => nil).update_all(column => Time.current, updated_at: Time.current) == 1
  end

  def notify_investor(change, kyc)
    users = investor_recipients(change, kyc)
    users.each do |user|
      InvestorKycNotifier.with(record: kyc, entity_id: kyc.entity_id, email_method: :notify_bank_details_changed,
                               msg: "Your bank details with #{kyc.entity.name} were changed", user_id: user.id,
                               bank_detail_change_id: change.id).deliver_later(user)
    end
    # Kept on the record: the note, the popup and the approver email say who was told
    change.update_columns(investor_recipient_ids: users.map(&:id))
  end

  # D8 — the KYC email rule (Investor#notification_users with the "KYC" tag, each passing InvestorKycPolicy#show?),
  # narrowed to contacts whose approved access was created before the change (E25)
  def investor_recipients(change, kyc)
    users = kyc.investor.notification_users(kyc, with_tag: "KYC")
    return [] if users.empty?

    existed = kyc.investor.approved_investor_accesses.where(user_id: users.map(&:id))
                 .where(created_at: ...change.created_at).distinct.pluck(:user_id).to_set
    users.select { |user| existed.include?(user.id) }.uniq(&:id)
  end

  def notify_approvers(change, kyc)
    approver_recipients(change, kyc).each do |user|
      InvestorKycNotifier.with(record: kyc, entity_id: kyc.entity_id, email_method: :notify_bank_change_review,
                               msg: "Bank details changed for #{kyc.full_name} — a second approver must verify",
                               user_id: user.id, bank_detail_change_id: change.id).deliver_later(user)
    end
  end

  # H8, E30 — the firm's own staff and advisors with a staff grant, as InvestorKyc#notify_kyc finds them, narrowed to
  # KYC approvers who can see this KYC; never the maker
  def approver_recipients(change, kyc)
    seen = Set.new
    recipients = []
    kyc.entity.employees.not_investor_advisor_roles.active.includes(:roles).find_each do |user|
      next if user.id == change.changed_by_id || !user.enable_kycs

      policy = InvestorKycPolicy.new(user, kyc)
      next unless policy.show? && policy.kyc_approver?

      seen << user.id
      recipients << user
    end
    kyc.entity.investor_advisors.includes(:user).find_each do |advisor|
      user = advisor.user
      next if user.nil? || !user.active || seen.include?(user.id) || user.id == change.changed_by_id
      next unless advisor.permissions.enable_kycs? && kyc.entity.permissions.enable_kycs?

      policy = InvestorKycPolicy.new(user, kyc)
      next unless policy.show? && policy.kyc_approver?

      seen << user.id
      recipients << user
    end
    recipients
  end
end
